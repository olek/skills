# Familiar

A Familiar lets your coding agent hand off a self-contained task to a subagent
while keeping the work visible. It opens one named, interactive agent beside the
summoner's terminal, where you can watch its progress and guide it directly. The
summoner writes the request and reads the result; durable files preserve both
across multiple working sessions. A Familiar can use the same setup as the
summoner or a different effort level, model, or even harness, letting you pick
the best tool for the job.

## Supported environments

So far, only Linux and the tmux split-window backend have been thoroughly
tested. It should be easy to get it to work on macOS inside Tmux. The direct
iTerm2 backend is experimental and may not work.

## Ask for a Familiar

Ask your agent to summon a Familiar and describe its task. You may choose
the harness, model, and effort. You can interact directly in the Familiar's
terminal while it works. It writes its complete result to a response file.

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
path. The request is staged at `antechamber/<name>.md`. When summoned, it moves to
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

Optional but strongly recommended `config/intent.conf` entries should look like
this, customized with your preferred models and efforts per harness and intent:

```ini
codex.planning = gpt-6-sol medium
codex.implementation = gpt-6-sol low
codex.review = gpt-6-sol high

claude.planning = claude-opus-5-5 medium
claude.implementation = claude-opus-5-5 low
claude.review = claude-opus-5-5 high
```

Valid intents are `planning`, `implementation`, and `review`. `default` lets the
harness choose that setting.

## Dependencies

The tmux backend needs Bash 4.3 or newer, tmux, and GNU core utilities, which
are generally available on Linux and can be installed on macOS with Homebrew.
The selected harness CLI must also be on `PATH` (`codex`, `claude`, `opencode`,
or `agy`).

### iTerm2 (experimental)

This backend is experimental and has not been validated on a Mac yet. It needs a
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
session as aborted without a response while it waits. A launch journal at
`recovery/<sha256(summoner id)>.json` blocks another launch when cleanup fails.
Use `dismiss.sh` from the same summoner session to close a live Familiar. The
record may not survive an iTerm2 restart.

For first-time Mac validation, use the
[iTerm2 backend checklist](scripts/lib/backends/iterm2-mac-initial-validation.md).

## Documentation

[SKILL.md](SKILL.md) is the agent procedure; [DESIGN.md](DESIGN.md) explains the
boundaries; [IMPLEMENTATION.md](IMPLEMENTATION.md) describes the scripts and
state; the [harness contract](scripts/lib/harnesses/README.md) and
[backend contract](scripts/lib/backends/README.md) guide extensions.
