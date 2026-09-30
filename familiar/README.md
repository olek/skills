# Familiar

A Familiar is one named, interactive agent in a visible terminal beside the
summoner terminal. tmux is established. iTerm2 is experimental and has not been
validated on a Mac. You can watch, guide, and dismiss the Familiar.

## Ask for a Familiar

Ask your agent to summon a named Familiar and describe its task. You may choose
`codex`, `claude`, `opencode`, or `antigravity`, plus a model and effort. The
Familiar's harness is independent of the summoner's. You can interact directly
in its terminal while it works. It writes its complete result to a response file.

Only Claude uses the launch session name. Codex, OpenCode, and Antigravity keep
their own session identifiers.

| Script | Purpose |
| --- | --- |
| `scripts/paths.sh --request-path --name <name>` | Stage a request path |
| `scripts/defaults.sh --harness <harness> --intent <intent>` | Resolve model and effort |
| `scripts/summon.sh` | Launch a Familiar |
| `scripts/status.sh` | Report delivery or wait |
| `scripts/message.sh` | Send a follow-up |
| `scripts/dismiss.sh` | Close the current Familiar terminal |

The agent procedure and exact options are in [SKILL.md](SKILL.md).

## Familiar home

The default home is `~/.familiar`; `FAMILIAR_HOME` overrides it with an absolute
path. The request is staged at `antechamber/<name>.md`. On summon it moves to
`summonings/YYMMDD-HHMM-rq-<name>.md`; the response uses the same timestamp and
`rs` in place of `rq`.

```text
~/.familiar/
  antechamber/
  config/
    intent.conf
  summonings/
  recovery/
```

The path query, defaults lookup, and launcher create the base layout. The iTerm2
bridge creates `recovery/` when it needs a launch journal.

## Configuration

- `FAMILIAR_HOME`: Familiar home.
- `FAMILIAR_BACKEND`: `auto`, `tmux`, or `iterm2`. Auto uses tmux if `TMUX` is
  set, then a direct iTerm2 session when `ITERM_SESSION_ID` is set and
  `TERM_PROGRAM` is `iTerm.app`.
- `FAMILIAR_AUTO_DISMISS_SECONDS`: Inspection interval, at most 60 seconds.
- `FAMILIAR_ITERM2_PYTHON`: Optional Python 3 executable with the `iterm2`
  package. Without it, Familiar uses `python3` when it imports `iterm2`, then
  tries the newest iTerm2 runtime under
  `~/Library/ApplicationSupport/iTerm2/iterm2env/versions/*/bin/python3`.

Optional `config/intent.conf` entries have this form:

```ini
codex.planning = my-planning-model medium
claude.review = my-review-model high
opencode.implementation = provider/my-model default
```

Valid intents are `planning`, `implementation`, and `review`. `default` lets the
harness choose that setting. OpenCode's TUI does not support an effort override.
Malformed lines and unknown harnesses fail lookup. Duplicate entries fail
lookup for every harness and intent.

## Requirements

The tmux backend needs Bash 4.3 or newer, tmux, GNU core utilities, and the
selected harness CLI on `PATH` (`codex`, `claude`, `opencode`, or `agy`).

### iTerm2 (experimental)

This backend is experimental and has not been validated on a Mac. It needs a
logged-in iTerm2 session, Bash 4.3 or newer, GNU `realpath` and `mv` (or
`grealpath` and `gmv` from Homebrew coreutils without `gnubin`), Python 3 with
the `iterm2` package, and Python API access. Install iTerm2's Python runtime
from its Scripts menu or install `iterm2` into another Python with
`pip install iterm2`. `FAMILIAR_ITERM2_PYTHON` selects a specific interpreter.
The iTerm2 Python API must be enabled in Settings > General > Magic, and macOS
Automation may ask to let the terminal or harness control iTerm2. If Apple
Events cannot be authorized, iTerm2's administrator-only
`Allow all apps to connect` option is an escape hatch.

The backend cannot run inside tmux. Auto selection ignores a stale
`ITERM_SESSION_ID` unless `TERM_PROGRAM=iTerm.app`; setting
`FAMILIAR_BACKEND=iterm2` explicitly bypasses that terminal-name check. A
one-shot launcher in `/tmp` uses the user's interactive login shell to load its
environment, then restores the summoner's `PATH` before starting the harness.
Shell startup files run in the Familiar pane. The launcher uses iTerm2's default
profile plus command and directory settings, avoiding profile command
interpolation and argument splitting. The default profile's colors and font may
differ from the summoner's. The launcher removes itself after it starts and
leaves a nonzero exit visible until Enter is pressed. `status.sh` reports that
session as ended without a response while it waits. A launch journal at
`recovery/<sha256(summoner id)>.json` blocks another launch when cleanup fails.
Use `dismiss.sh` from the same summoner session to close a live Familiar. The
record may not survive an iTerm2 restart.

Codex allow rules authorize the Familiar scripts to run; they do not grant
access to iTerm2's Unix socket or macOS Automation. If Codex's sandbox blocks
either, run with `danger-full-access` or approve each call.

### Mac validation checklist

Run these checks from the skill directory before treating the backend as usable.

1. In Settings > General > Magic, enable the Python API and install the Python
   runtime from iTerm2's Scripts menu. Verify `iterm2` imports with
   `python3 -c 'import iterm2; print(iterm2.__file__)'`, or set
   `FAMILIAR_ITERM2_PYTHON` to that runtime. Familiar checks for the package
   without importing it on each bridge call.
2. Check `bash --version` (4.3 or newer must be first on `PATH`). Check that
   either `realpath` and `mv`, or `grealpath` and `gmv`, report GNU coreutils.
   On a Mac with Bash 3.2 at `/bin/bash`, `/bin/bash scripts/status.sh` should
   print the Bash 4.3 requirement and exit 1.
3. From a plain iTerm2 tab with no tmux, first `cd` to the skill directory.
   Run `bash -c 'source scripts/lib/backends/iterm2.sh && familiar_backend_require_context'`
   three times. Record which app receives the Automation prompt and whether a
   prompt appears on each call.
4. Run `scripts/status.sh`. Expect `No managed Familiar exists`; this checks
   the session lookup and metadata read.
5. Check the launcher cwd, quoting, PATH, and shell environment:

   ```bash
   mkdir -p "$HOME/tmp/it2 o'k \\x"
   bash -c '
     source scripts/lib/harness.sh
     source scripts/lib/backend.sh
     familiar_backend_require_context
     familiar_backend_launch_familiar "${ITERM_SESSION_ID#*:}" "$1" "$2" probe "$(date +%y%m%d-%H%M)" codex "${FAMILIAR_HOME:-$HOME/.familiar}"
   ' familiar-launch "$HOME/tmp/it2 o'k \\x" "/bin/sh -c 'pwd; env | cut -d= -f1 | sort > /tmp/familiar-env-names.txt; sleep 30'"
   scripts/dismiss.sh
   ```

   The pane should show the requested cwd. In a normal iTerm2 tab, run
   `comm -23 <(env | cut -d= -f1 | sort) /tmp/familiar-env-names.txt` to list
   variables missing from the Familiar without writing secret values to disk.
   Check `NODE_EXTRA_CA_CERTS`, `HTTPS_PROXY`, `ANTHROPIC_*`,
   `CLAUDE_CODE_USE_BEDROCK`, `AWS_PROFILE`, `OPENAI_API_KEY`, `CODEX_HOME`,
   `CLAUDE_CONFIG_DIR`, and `FAMILIAR_HOME`.
6. Run `scripts/summon.sh` for Claude and Codex. Run `status.sh`, send a two-line
   message with `message.sh` and confirm one submit, then run `dismiss.sh`.
   Confirm the pane closes and status is clean.
7. From a second tab, run `status.sh` and `dismiss.sh`; neither should see or
   close the first tab's Familiar. Move the summoner tab to another window and
   check status again. Restart iTerm2 and check whether its session metadata
   remains. Enable Broadcast Input and confirm `message.sh` reaches only the
   Familiar.
8. Check the split/launcher race with a stub `codex` that sleeps:

   ```bash
   probe_bin=$(mktemp -d)
   printf '#!/bin/sh\nsleep 60\n' > "$probe_bin/codex"
   chmod +x "$probe_bin/codex"
   (
     set -e
     PATH="$probe_bin:$PATH"
     export PATH
     for name in race-1 race-2 race-3 race-4 race-5 race-6 race-7 race-8 race-9 race-10; do
       scripts/summon.sh --name "$name" --cwd "$PWD" --harness codex
       scripts/status.sh
       scripts/dismiss.sh
     done
   )
   rm -rf "$probe_bin"
   ls /tmp/familiar-launch.* 2>/dev/null
   ```

   Each status should say `awaiting response`; the final `ls` should print
   nothing. Repeat the status and summon checks from Codex with
   `examples/codex/familiar.rules` installed, and from Claude. In each tool
   shell, inspect `env | grep -E '^(TERM_PROGRAM|ITERM_SESSION_ID|TMUX)='` and
   record any socket or Automation denial.
9. Check failure paths with harness stubs that exit 0 and 3. A clean exit should
   close the pane and leave status ended. A nonzero exit should show the failure
   and wait for Enter while `status.sh` reports
   `ended without response`; press Enter and check status again. Also disable
   the Python API, quit iTerm2 before running the bridge from another terminal,
   and deny Automation; each error should identify its cause. From Claude with
   its sandbox enabled, check that `/tmp` permits the launcher to be created.

## Documentation

[SKILL.md](SKILL.md) is the agent procedure; [DESIGN.md](DESIGN.md) explains the
boundaries; [IMPLEMENTATION.md](IMPLEMENTATION.md) describes the scripts and
state; the [harness contract](scripts/lib/harnesses/README.md) and
[backend contract](scripts/lib/backends/README.md) guide extensions.
