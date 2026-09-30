#!/usr/bin/env python3
"""One-shot, exact-session iTerm2 transport for Familiar."""
import asyncio
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

VARIABLE = "user.familiar_managed"
EXIT_VARIABLE = "user.familiar_exit"


class BridgeError(Exception):
    pass


def recovery_path(summoner_id):
    home = Path(os.environ["FAMILIAR_CANONICAL_HOME"])
    digest = hashlib.sha256(summoner_id.encode()).hexdigest()
    return home / "recovery" / (digest + ".json")


def write_recovery(path, record):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".familiar-")
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def clear_recovery(path):
    path.unlink(missing_ok=True)


def ensure_can_launch(app, record, marker, path, message):
    if marker:
        raise BridgeError("iTerm2 Familiar session needs recovery before another launch: " + str(path))
    if record and app.get_session_by_id(record["familiar"]):
        raise BridgeError(message)


async def close_and_clear(familiar, marker_path):
    await familiar.async_close(force=True)
    clear_recovery(marker_path)


async def op_list(app, record, marker, marker_path, output):
    record = marker or record
    if not record:
        return
    if not record.get("familiar"):
        raise BridgeError("iTerm2 launch needs recovery before the Familiar session ID was recorded: " + str(marker_path))
    familiar = app.get_session_by_id(record["familiar"])
    dead = familiar is None
    if familiar is not None:
        dead = await familiar.async_get_variable(EXIT_VARIABLE) is not None
    print("\t".join((record["familiar"], record["name"], record["timestamp"], record["harness"], record["home"], "1" if dead else "0")), file=output)


def op_can_launch(app, record, marker, marker_path):
    ensure_can_launch(app, record, marker, marker_path,
                      "This summoning agent instance already has a managed Familiar; close it before summoning another")


async def op_launch(iterm2, app, summoner, summoner_id, record, marker, marker_path, rest, output):
    ensure_can_launch(app, record, marker, marker_path,
                      "A managed Familiar is still live or needs recovery")
    cwd, name, timestamp, harness, home, launcher = rest
    if not os.path.isabs(launcher) or not re.fullmatch(r"[A-Za-z0-9/._-]+", launcher):
        raise BridgeError("iTerm2 launch script path contains unsupported characters")
    new_record = dict(summoner=summoner_id, familiar="", name=name, timestamp=timestamp, harness=harness, home=home)
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_command("/bin/sh " + launcher)
    profile.set_use_custom_command("Yes")
    profile.set_custom_directory(cwd)
    profile.set_initial_directory_mode(iterm2.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM)
    profile.set_close_sessions_on_end(True)
    write_recovery(marker_path, new_record)
    try:
        familiar = await summoner.async_split_pane(vertical=True, before=False, profile_customizations=profile)
    except Exception:
        clear_recovery(marker_path)
        raise
    if familiar is None or not familiar.session_id:
        clear_recovery(marker_path)
        raise BridgeError("iTerm2 split returned no Familiar session")
    new_record["familiar"] = familiar.session_id
    try:
        write_recovery(marker_path, new_record)
    except Exception as error:
        try:
            await close_and_clear(familiar, marker_path)
        except Exception as cleanup_error:
            print("Recovery required for iTerm2 Familiar session %s after journal update failure: %s; cleanup: %s." % (familiar.session_id, error, cleanup_error), file=sys.stderr)
            return 3
        raise BridgeError("Recovery journal update failed; Familiar session closed: " + str(error))
    try:
        await summoner.async_set_variable(VARIABLE, new_record)
        if await summoner.async_get_variable(VARIABLE) != new_record:
            raise BridgeError("iTerm2 did not retain Familiar metadata")
    except Exception as error:
        try:
            await familiar.async_close(force=True)
            if await summoner.async_get_variable(VARIABLE) != record:
                await summoner.async_set_variable(VARIABLE, record)
            clear_recovery(marker_path)
        except Exception as cleanup_error:
            print("Recovery required for iTerm2 Familiar session %s: %s." % (familiar.session_id, cleanup_error), file=sys.stderr)
            return 3
        raise BridgeError("Metadata failed; Familiar session closed: " + str(error))
    try:
        clear_recovery(marker_path)
    except Exception as error:
        print("Recovery required for iTerm2 Familiar session %s; could not clear the recovery journal: %s." % (familiar.session_id, error), file=sys.stderr)
        return 3
    print(familiar.session_id, file=output)


async def op_owned(app, summoner, record, marker, marker_path, operation, rest):
    record = marker or record
    if not record or not rest or record["familiar"] != rest[0]:
        raise BridgeError("Familiar is not owned by the invoking iTerm2 session")
    familiar = app.get_session_by_id(record["familiar"])
    if familiar is None:
        raise BridgeError("Managed Familiar session is closed")
    if operation == "send":
        await familiar.async_send_text(sys.stdin.read(), suppress_broadcast=True)
    elif operation == "submit":
        await familiar.async_send_text("\r", suppress_broadcast=True)
    elif operation == "close":
        await familiar.async_close(force=True)
        if await summoner.async_get_variable(VARIABLE) == record:
            await summoner.async_set_variable(VARIABLE, None)
        if marker:
            clear_recovery(marker_path)


async def operate(iterm2, args, output):
    operation, summoner_id, *rest = args
    os.environ.pop("ITERM2_COOKIE", None)
    os.environ.pop("ITERM2_KEY", None)
    try:
        iterm2.auth.authenticate()
    except iterm2.auth.AuthenticationException as error:
        raise BridgeError("iTerm2 authentication failed: %s; enable Settings > General > Magic > Enable Python API and allow Automation for this terminal or harness" % error)
    except PermissionError:
        raise
    except Exception as error:
        raise BridgeError("iTerm2 authentication failed (%s: %s); enable Settings > General > Magic > Enable Python API and allow Automation for this terminal or harness" % (type(error).__name__, error))
    connection = await iterm2.Connection.async_create()
    app = await iterm2.async_get_app(connection)
    if app is None:
        raise BridgeError("No local iTerm2 GUI connection is available")
    summoner = app.get_session_by_id(summoner_id)
    if summoner is None or summoner.session_id != summoner_id:
        raise BridgeError("Invoking iTerm2 session ID does not resolve exactly: " + summoner_id)
    record = await summoner.async_get_variable(VARIABLE)
    if record and record.get("summoner") != summoner_id:
        raise BridgeError("Managed record belongs to another summoner")
    marker_path = recovery_path(summoner_id)
    marker = json.loads(marker_path.read_text()) if marker_path.exists() else None
    if marker and marker.get("summoner") != summoner_id:
        raise BridgeError("Recovery record belongs to another summoner")
    operations = {
        "check": lambda: None,
        "list": lambda: op_list(app, record, marker, marker_path, output),
        "can-launch": lambda: op_can_launch(app, record, marker, marker_path),
        "launch": lambda: op_launch(iterm2, app, summoner, summoner_id, record, marker, marker_path, rest, output),
        "send": lambda: op_owned(app, summoner, record, marker, marker_path, operation, rest),
        "submit": lambda: op_owned(app, summoner, record, marker, marker_path, operation, rest),
        "close": lambda: op_owned(app, summoner, record, marker, marker_path, operation, rest),
    }
    if operation not in operations:
        raise BridgeError("Unknown iTerm2 operation: " + operation)
    result = operations[operation]()
    if asyncio.iscoroutine(result):
        return await result
    return result


def main():
    try:
        import iterm2
    except ImportError as error:
        print("iTerm2 Python package unavailable: " + str(error) + ".", file=sys.stderr)
        return 1
    try:
        output = sys.stdout
        with contextlib.redirect_stdout(sys.stderr):
            result = asyncio.run(operate(iterm2, sys.argv[1:], output))
        return result or 0
    except Exception as error:
        message = str(error)
        if "401" in message:
            message = "iTerm2 Python API permission denied (401); enable API access and allow Automation"
        elif isinstance(error, PermissionError):
            message = "iTerm2 Python API access was denied by the local sandbox; allow the iTerm2 socket and Apple Events or approve this call: " + message
        elif "refused" in message.lower() or "connect" in message.lower():
            message = "iTerm2 Python API connection failed; enable the API and check the local GUI: " + message
        print(message.rstrip(".") + ".", file=sys.stderr)
        return 1
    except SystemExit:
        print("iTerm2 Python package is too old for this iTerm2 version; upgrade the package.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
