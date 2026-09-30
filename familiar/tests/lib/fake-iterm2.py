"""Persistent fake of the iTerm2 methods used by Familiar."""
import enum
import json
import os
import re
import sys

PATH = os.environ["FAKE_ITERM2_STATE"]


def load():
    with open(PATH) as stream:
        state = json.load(stream)
    for session in state["sessions"].values():
        value = session.get("variable")
        if isinstance(value, dict):
            session["variable"] = json.dumps(value)
    return state


def save(state):
    with open(PATH, "w") as stream:
        json.dump(state, stream)


def set_test_variable(session_id, name, value):
    state = load()
    session = state["sessions"][session_id]
    session.setdefault("user_variables", {})[name] = value
    save(state)


class AuthenticationException(Exception):
    pass


class auth:
    AuthenticationException = AuthenticationException

    @staticmethod
    def authenticate():
        state = load()
        failure = state.get("fail")
        state["auth_calls"] = state.get("auth_calls", 0) + 1
        save(state)
        reasons = {
            "auth-api-disabled": "execution error: The Python API is not enabled.",
            "auth-not-running": "iTerm2 not running",
            "auth-old-version": "iTerm2 version too old",
            "auth-tcc-denied": "execution error: Not authorized to send Apple events to iTerm2.",
        }
        if failure in reasons:
            raise AuthenticationException(reasons[failure])
        if failure == "auth-error":
            raise RuntimeError("AppleScript error text had no trailing error code")
        os.environ["ITERM2_COOKIE"] = "fresh-fake-cookie"
        os.environ["ITERM2_KEY"] = "fresh-fake-key"
        return True


class InvalidStatusCode(Exception):
    def __init__(self, status_code):
        self.status_code = status_code
        super().__init__(str(status_code))


class Connection:
    @staticmethod
    async def async_create():
        state = load()
        failure = state.get("fail")
        state["auth_environment"] = {
            "cookie": os.environ.get("ITERM2_COOKIE"),
            "key": os.environ.get("ITERM2_KEY"),
        }
        save(state)
        if not os.environ.get("ITERM2_COOKIE"):
            try:
                auth.authenticate()
            except AuthenticationException:
                pass
        if failure == "406":
            print("This version of the iterm2 module is too old for the current version of iTerm2. Please upgrade.")
            raise SystemExit(1)
        if failure == "permission":
            raise PermissionError("operation not permitted")
        if failure == "connect":
            raise RuntimeError("connection refused")
        if failure == "401" or failure in (
            "auth-api-disabled", "auth-not-running", "auth-old-version", "auth-tcc-denied"
        ):
            raise InvalidStatusCode(401)
        return Connection()


class App:
    instance = None

    def get_session_by_id(self, session_id):
        return Session(session_id) if session_id in load()["sessions"] else None


async def async_get_app(connection, create_if_needed=True):
    if App.instance is None:
        if not create_if_needed:
            return None
        App.instance = App()
    return App.instance


def components_in_shell_command(command):
    words = []
    current = []
    quote = None
    escaped = False
    started = False
    escaped_controls = {"n": "\n", "a": "\a", "t": "\t", "r": "\r"}
    for character in command:
        if escaped:
            if character in escaped_controls:
                current.append(escaped_controls[character])
            elif quote == '"' and character not in ('"', "\\"):
                current.extend(("\\", character))
            elif quote == "'" and character != "'":
                current.extend(("\\", character))
            elif quote == "'" and character == "'":
                current.append("\\")
            else:
                current.append(character)
            escaped = False
            started = True
        elif character == "\\":
            escaped = True
            started = True
        elif quote:
            if character == quote:
                quote = None
            else:
                current.append(character)
        elif character in ("'", '"'):
            quote = character
            started = True
        elif character.isspace():
            if started:
                words.append("".join(current))
                current = []
                started = False
        else:
            current.append(character)
            started = True
    if escaped:
        current.append("\\")
    if quote:
        raise ValueError("unclosed quote")
    if started:
        words.append("".join(current))
    return words


def profile_values(profile):
    if profile is None:
        return {}
    return {key: json.loads(value) for key, value in profile.values.items()}


def mark_exec_failure(state, target, argv0):
    state["events"].append(["exec-failed", argv0])
    if state.get("sessions", {}).get(target) is not None:
        values = state["events"][-2][4] if len(state["events"][-2]) > 4 and state["events"][-2][0] == "split" else {}
        settings = {key: json.loads(value) for key, value in values.items()}
        if settings.get("Close Sessions On End"):
            del state["sessions"][target]
    save(state)


class Session:
    def __init__(self, session_id):
        self.session_id = session_id

    async def async_get_variable(self, name):
        if not re.fullmatch(r"user\.[^.]+", name):
            raise RuntimeError("InvalidVariableName")
        state = load()
        if state.get("fail") == "list" and sys.argv[1] == "list":
            raise RuntimeError("list RPC failed")
        if name == "user.familiar_exit":
            return state["sessions"][self.session_id].get("user_variables", {}).get(name)
        stored = state["sessions"][self.session_id].get("variable")
        return None if stored is None else json.loads(stored)

    async def async_set_variable(self, name, value):
        if not re.fullmatch(r"user\.[^.]+", name):
            raise RuntimeError("InvalidVariableName")
        state = load()
        if state.get("fail") in ("metadata", "metadata-close"):
            raise RuntimeError("metadata failed")
        if state.get("fail") == "metadata-silent":
            return
        state["sessions"][self.session_id]["variable"] = json.dumps(value)
        state["events"].append(["set", self.session_id, value])
        save(state)

    async def async_split_pane(self, vertical=False, before=False, profile=None, profile_customizations=None):
        state = load()
        if state.get("fail") == "split":
            raise RuntimeError("split failed")
        target = state.get("next_target", "target-A")
        settings = profile_values(profile_customizations)
        state["sessions"][target] = {}
        event = ["split", self.session_id, vertical, before,
                 profile_customizations.values.copy() if profile_customizations else {}]
        command = settings.get("Command", "")
        if "\\(" in command:
            state["events"].append(event)
            save(state)
            mark_exec_failure(state, target, "swifty-interpolation")
            return Session(target)
        try:
            argv = components_in_shell_command(command)
        except ValueError:
            argv = []
        executable = argv[0] if argv else ""
        valid_executable = executable.startswith("/") and os.path.isfile(executable) and os.access(executable, os.X_OK)
        launcher = argv[1] if executable == "/bin/sh" and len(argv) > 1 else ""
        valid_launcher = executable != "/bin/sh" or (launcher and os.path.isfile(launcher))
        if not valid_executable or not valid_launcher:
            state["events"].append(event)
            save(state)
            mark_exec_failure(state, target, executable or "<empty>")
            return Session(target)
        if launcher:
            state["sessions"][target]["launcher"] = launcher
        state["events"].append(event)
        save(state)
        return Session(target)

    async def async_send_text(self, text, suppress_broadcast=False):
        state = load()
        if state.get("fail") == "send" or (state.get("fail") == "submit" and text == "\r"):
            raise RuntimeError("send failed")
        if state["sessions"][self.session_id].get("exited"):
            raise RuntimeError("SessionNotFound")
        state["events"].append(["send", self.session_id, text, suppress_broadcast])
        save(state)

    async def async_close(self, force=False):
        state = load()
        if state.get("fail") in ("close", "metadata-close"):
            raise RuntimeError("close failed")
        state["events"].append(["close", self.session_id, force])
        del state["sessions"][self.session_id]
        save(state)


class InitialWorkingDirectory(enum.Enum):
    INITIAL_WORKING_DIRECTORY_CUSTOM = "Yes"


class LocalWriteOnlyProfile:
    def __init__(self):
        self.values = {}

    def _set(self, key, value):
        self.values[key] = json.dumps(value)

    def set_command(self, value):
        self._set("Command", value)

    def set_use_custom_command(self, value):
        self._set("Custom Command", value)

    def set_custom_directory(self, value):
        self._set("Working Directory", value)

    def set_initial_directory_mode(self, value):
        self._set("Custom Directory", value.value)

    def set_close_sessions_on_end(self, value):
        self._set("Close Sessions On End", value)
