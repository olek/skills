# Familiar implementation

tmux is established; iTerm2 is experimental, untested on a Mac, and likely not
working yet.

## Components

| Component | Role |
| --- | --- |
| `scripts/paths.sh` | Home layout, validation, and filenames |
| `scripts/defaults.sh` and `scripts/lib/intent-config.sh` | Read user intent choices |
| `scripts/summon.sh` | Promote the request and launch the Familiar |
| `scripts/status.sh` | Report delivery and optionally wait |
| `scripts/message.sh` | Send literal text and Enter |
| `scripts/dismiss.sh` | Close the current Familiar terminal |
| `scripts/lib/familiar.sh` | Resolve one live managed Familiar |
| `scripts/lib/backend.sh` and `scripts/lib/backends/` | Select and operate a terminal backend |
| `scripts/lib/harness.sh` and `scripts/lib/harnesses/` | Load a harness and build its command |

The [backend contract](scripts/lib/backends/README.md) and
[harness contract](scripts/lib/harnesses/README.md) define extension points.

## Files and completion

`FAMILIAR_HOME` defaults to `~/.familiar`. A request starts at
`antechamber/<name>.md`. The launcher captures local time once and promotes it
to `summonings/YYMMDD-HHMM-rq-<name>.md`; the response uses `rs`. The shared
path builder derives both paths from the home, timestamp, and name. Existing
request or response paths stop the launch. The launcher injects the resolved
request and response paths, requires the Familiar to write its complete result
once, and asks it to announce completion in its terminal.

The base layout includes `antechamber/`, `config/`, and `summonings/`. The iTerm2
bridge creates `recovery/<sha256(summoner id)>.json` before splitting a terminal.
It updates the journal with the Familiar ID, then records management metadata on
the summoner session and clears the journal. If cleanup fails, the journal
blocks another launch until scoped dismissal closes the Familiar and clears it.

## Launch and status

The launcher validates the name, working directory, selected harness, and
terminal context, then builds the harness command. It promotes the staged
request before terminal launch. A launch failure restores the staged request
after successful cleanup. Backend exit status 3 means cleanup failed and the
promoted request stays in place for recovery.

| Row state | Status text | Wait result |
| --- | --- | --- |
| `invalid-metadata` | Invalid metadata; paths unavailable | Failed |
| `delivered` | Response delivered | Delivered |
| `ended` | Ended without response | Failed |
| `invalid` | Response path invalid | Failed |
| `awaiting` | Awaiting response | Waiting |

A closed terminal without a response is `ended`, even if the response path is a
directory. `--wait` polls for delivery or failure. `--wait --auto-dismiss` adds
an inspection interval of up to 60 seconds, then closes a remaining live
Familiar terminal. `--timeout` requires `--wait`.

## Backend metadata

tmux stores these pane options and marks `@familiar` last, after all other
metadata is set:

| Option | Value |
| --- | --- |
| `@familiar` | Managed marker `1` |
| `@familiar_name` | Bare name |
| `@familiar_timestamp` | Launch timestamp |
| `@familiar_harness` | Harness name |
| `@familiar_home` | Canonical Familiar home |
| `@familiar_summoner_pane` | Summoner pane ID |

The iTerm2 record stores `summoner`, `familiar`, `name`, `timestamp`, `harness`,
and `home` on the summoner session. The recovery journal uses the same record
shape. Dismissal clears the managed record and any journal.

Claude receives the session name `YYMMDD-HHMM-fm-<name>` and an alternate-screen
override scoped to its process. Codex, OpenCode, and Antigravity do not use the
session name.

## Tests

```bash
bash tests/test-runner.sh
shellcheck -x scripts/*.sh scripts/lib/*.sh scripts/lib/backends/*.sh scripts/lib/harnesses/*.sh tests/test-runner.sh
python3 -m py_compile scripts/lib/backends/iterm2-bridge.py tests/lib/fake-iterm2.py
```

The runner sources one entry point per case file. Fake tmux and harness commands
are in `tests/lib/test-helper.sh`; the fake iTerm2 API is
`tests/lib/fake-iterm2.py`. Intent configuration cases are in
`tests/cases/defaults.sh`.
