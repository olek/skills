#!/usr/bin/env python3
"""One-shot, exact-session iTerm2 transport for Familiar."""
import asyncio
import json
import sys

VARIABLE = "user.familiar_managed"


class BridgeError(Exception):
    pass


async def operate(iterm2, args):
    operation, origin_id, *rest = args
    connection = await iterm2.Connection.async_create()
    app = await iterm2.async_get_app(connection, create_if_needed=False)
    if app is None:
        raise BridgeError("No local iTerm2 GUI connection is available")
    origin = app.get_session_by_id(origin_id)
    if origin is None or origin.session_id != origin_id:
        raise BridgeError("Invoking iTerm2 session ID does not resolve exactly: " + origin_id)
    record = await origin.async_get_variable(VARIABLE)
    if isinstance(record, str):
        record = json.loads(record)
    if record and record.get("origin") != origin_id:
        raise BridgeError("Managed record belongs to another origin")
    if operation == "check":
        return
    if operation == "list":
        if record:
            target = app.get_session_by_id(record["target"])
            print("\t".join((record["target"], record["name"], record["timestamp"], record["harness"], record["home"], "0" if target else "1")))
        return
    if operation == "can-launch":
        if record and (app.get_session_by_id(record["target"]) or record.get("recovery")):
            raise BridgeError("This summoning agent instance already has a managed Familiar; close it before summoning another")
        return
    if operation == "launch":
        cwd, name, timestamp, harness, home = rest
        if record and (app.get_session_by_id(record["target"]) or record.get("recovery")):
            raise BridgeError("A managed Familiar is still live or needs recovery")
        command = sys.stdin.read()
        profile = iterm2.LocalWriteOnlyProfile()
        profile.set_command(command)
        profile.set_use_custom_command("Yes")
        profile.set_custom_directory(cwd)
        profile.set_initial_directory_mode(iterm2.InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM)
        profile.set_close_sessions_on_end(True)
        target = await origin.async_split_pane(vertical=True, before=False, profile_customizations=profile)
        if target is None or not target.session_id:
            raise BridgeError("iTerm2 split returned no target session")
        new_record = dict(origin=origin_id, target=target.session_id, name=name, timestamp=timestamp, harness=harness, home=home)
        try:
            await origin.async_set_variable(VARIABLE, new_record)
            if await origin.async_get_variable(VARIABLE) != new_record:
                raise BridgeError("iTerm2 did not retain Familiar metadata")
        except Exception as error:
            try:
                await target.async_close(force=True)
                if await origin.async_get_variable(VARIABLE) != record:
                    await origin.async_set_variable(VARIABLE, record)
            except Exception as cleanup_error:
                new_record["recovery"] = True
                try:
                    await origin.async_set_variable(VARIABLE, new_record)
                except Exception:
                    pass
                print("Recovery required for iTerm2 target %s: %s" % (target.session_id, cleanup_error), file=sys.stderr)
                return 3
            raise BridgeError("Metadata failed; target closed: " + str(error))
        print(target.session_id)
        return
    if not record or not rest or record["target"] != rest[0]:
        raise BridgeError("Target is not owned by the invoking iTerm2 session")
    target = app.get_session_by_id(record["target"])
    if target is None:
        raise BridgeError("Managed iTerm2 target is closed")
    if operation == "send":
        await target.async_send_text(sys.stdin.read(), suppress_broadcast=True)
    elif operation == "submit":
        await target.async_send_text("\r", suppress_broadcast=True)
    elif operation == "close":
        await target.async_close(force=True)
    else:
        raise BridgeError("Unknown iTerm2 operation: " + operation)


def main():
    try:
        import iterm2
    except ImportError as error:
        print("iTerm2 Python package unavailable: " + str(error), file=sys.stderr)
        return 1
    try:
        result = asyncio.run(operate(iterm2, sys.argv[1:]))
        return result or 0
    except Exception as error:
        message = str(error)
        if "401" in message:
            message = "iTerm2 Python API permission denied (401); enable API access and allow Automation"
        elif "refused" in message.lower() or "connect" in message.lower():
            message = "iTerm2 Python API connection failed; enable the API and check the local GUI: " + message
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
