"""Persistent fake of the iTerm2 methods used by Familiar."""
import json
import os

PATH = os.environ["FAKE_ITERM2_STATE"]


def load():
    with open(PATH) as stream:
        return json.load(stream)


def save(state):
    with open(PATH, "w") as stream:
        json.dump(state, stream)


class Connection:
    @staticmethod
    async def async_create():
        state = load()
        if state.get("fail") == "connect":
            raise RuntimeError("connection refused")
        return Connection()


async def async_get_app(connection, create_if_needed=False):
    state = load()
    if state.get("fail") == "401":
        raise RuntimeError("401")
    return App()


class App:
    def get_session_by_id(self, session_id):
        return Session(session_id) if session_id in load()["sessions"] else None


class Session:
    def __init__(self, session_id):
        self.session_id = session_id

    async def async_get_variable(self, name):
        return load()["sessions"][self.session_id].get("variable")

    async def async_set_variable(self, name, value):
        state = load()
        if state.get("fail") == "metadata":
            raise RuntimeError("metadata failed")
        state["sessions"][self.session_id]["variable"] = value
        state["events"].append(["set", self.session_id, value])
        save(state)

    async def async_split_pane(self, vertical=False, before=False, profile_customizations=None):
        state = load()
        if state.get("fail") == "split":
            raise RuntimeError("split failed")
        target = state.get("next_target", "target-A")
        state["sessions"][target] = {}
        state["events"].append(["split", self.session_id, vertical, before, profile_customizations.settings])
        save(state)
        return Session(target)

    async def async_send_text(self, text, suppress_broadcast=False):
        state = load()
        if state.get("fail") == "send" or (state.get("fail") == "submit" and text == "\r"):
            raise RuntimeError("send failed")
        state["events"].append(["send", self.session_id, text, suppress_broadcast])
        save(state)

    async def async_close(self, force=False):
        state = load()
        if state.get("fail") == "close":
            raise RuntimeError("close failed")
        state["events"].append(["close", self.session_id, force])
        del state["sessions"][self.session_id]
        save(state)


class InitialWorkingDirectory:
    INITIAL_WORKING_DIRECTORY_CUSTOM = "Yes"


class LocalWriteOnlyProfile:
    def __init__(self):
        self.settings = {}

    def set_command(self, value):
        self.settings["command"] = value

    def set_use_custom_command(self, value):
        self.settings["use_custom_command"] = value

    def set_custom_directory(self, value):
        self.settings["custom_directory"] = value

    def set_initial_directory_mode(self, value):
        self.settings["initial_directory_mode"] = value

    def set_close_sessions_on_end(self, value):
        self.settings["close_sessions_on_end"] = value
