# Familiar

A Familiar is one named, interactive agent in a visible terminal beside the
summoner terminal. tmux is established. iTerm2 is experimental, untested on a
Mac, and likely not working yet. You can watch, guide, and dismiss the Familiar.

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
  set, then a direct iTerm2 session if `ITERM_SESSION_ID` is set.
- `FAMILIAR_AUTO_DISMISS_SECONDS`: Inspection interval, at most 60 seconds.
- `FAMILIAR_ITERM2_PYTHON`: Python 3 executable with the `iterm2` package.

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

The tmux backend needs Bash, tmux, GNU core utilities, and the selected harness
CLI on `PATH` (`codex`, `claude`, `opencode`, or `agy`).

### iTerm2 (experimental)

Untested on a Mac. It needs a logged-in macOS iTerm2 session, Bash 4.3 or newer,
GNU `realpath` and `mv`, Python 3 with `iterm2`, and Python API and Automation
permissions. It cannot run inside tmux. A launch journal at
`recovery/<sha256(summoner id)>.json` blocks a new launch when cleanup fails.
Use `dismiss.sh` from the same summoner session to close the recorded Familiar.
The record may not survive app restart.

Before relying on this backend, validate on a Mac:

- `ITERM_SESSION_ID` maps exactly to the Python API session ID.
- Splitting starts the command in the requested working directory.
- Close-on-end status and scoped dismissal work.
- Python API and Automation permissions work for an external script.

## Documentation

[SKILL.md](SKILL.md) is the agent procedure; [DESIGN.md](DESIGN.md) explains the
boundaries; [IMPLEMENTATION.md](IMPLEMENTATION.md) describes the scripts and
state; the [harness contract](scripts/lib/harnesses/README.md) and
[backend contract](scripts/lib/backends/README.md) guide extensions.
