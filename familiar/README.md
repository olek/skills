# Familiar

A Familiar is one named, interactive agent that runs in a visible terminal pane
beside the session that summoned it. tmux is the established backend. iTerm2
support is experimental and has not been tested on a Mac. Unlike a headless
sub-agent, you watch it reason, correct it mid-task, answer its questions, and
dismiss it - one companion at a time, in view and in conversation.

This README is for people using the plugin. For how the agent drives it, see
[SKILL.md](SKILL.md); for why it is built this way and how to extend it, see
[DESIGN.md](DESIGN.md).

## Summoning one

Ask your Claude Code or Codex session for a named familiar, sidekick, companion,
or sub-agent, or just say "summon the Familiar", and describe the task. The
summoning agent writes a self-contained request, opens the pane, and reports
where the Familiar lives. Ordinary headless sub-agents still handle background
parallel work you did not ask to see.

## Mixing harnesses and models

The Familiar's engine is independent of your own: a Codex session can summon a
Claude Familiar and vice versa. By default the summoning agent reuses its own
harness, but you can name `codex`, `claude`, `opencode`, or `antigravity` and
pick the model and reasoning effort supported by that harness. Without an
explicit choice or matching intent entry, the target harness uses its
configured model and effort. Explicit values are passed through unchanged,
without translation between vendors.

## Working with the pane

The Familiar runs its native TUI in a real pane, not a log. Read along, type
corrections, and answer its prompts directly. When it finishes it writes the
complete result to a response file and says so in the pane. It makes every file
change itself and inherits the permission defaults configured locally for its
harness; it may hand read-only lookups to cheaper headless helpers.

The public wrappers are `scripts/summon.sh` for launching,
`scripts/status.sh` for delivery state, `scripts/message.sh` for follow-ups,
and `scripts/dismiss.sh` for dismissal. The follow-up and dismissal
wrappers resolve the managed pane from metadata on the selected terminal
backend, so they do not accept an arbitrary pane target.

Check delivery with `scripts/status.sh`. To wait for completion, invoke
`scripts/status.sh --wait` once; add `--auto-dismiss` to dismiss a remaining
live pane after its inspection interval.

Send a follow-up with `scripts/message.sh --message '<text>'`. It
requires exactly one live managed Familiar for the current summoning terminal
session.

Dismiss that Familiar with `scripts/dismiss.sh`. It accepts no pane ID
and rejects zero, closed-only, or multiple live matches.

## Spotting the session

A Claude Familiar launches with a readable session name
(`YYMMDD-HHMM-fm-<name>`), so the session picker, window title, and status line
show a label instead of a UUID. Codex has no launch-time naming flag, so a
Codex Familiar keeps its default identifier unless you rename it from its TUI.

## Where things live

Requests and responses are durable files under the Familiar home's
`summonings` subdirectory. Before launch, your request waits briefly in the
`antechamber` subdirectory under an untimestamped name; at summon time it is
promoted to a timestamped path so same-day artifacts sort chronologically:

| File | Name |
| --- | --- |
| request | `YYMMDD-HHMM-rq-<name>.md` |
| response | `YYMMDD-HHMM-rs-<name>.md` |

The default layout is:

```text
~/.familiar/
  antechamber/
  config/
    intent.conf
  summonings/
```

Familiar creates these directories when it prepares a request, resolves intent
defaults, or launches a summon. The intent file remains optional.

## Configuration

- `FAMILIAR_HOME`: Absolute Familiar home containing `antechamber`, `config`,
  and `summonings`. Overrides the built-in default.
- `FAMILIAR_AUTO_DISMISS_SECONDS`: Seconds a delivered pane stays open for
  inspection before automatic dismissal, up to 60 (the default).
- `FAMILIAR_BACKEND`: `auto` (default), `tmux`, or `iterm2`. Automatic selection
  uses tmux when `TMUX` is set, then iTerm2 when `ITERM_SESSION_ID` is set.
  Otherwise scripts fail with a terminal-backend error.
- `FAMILIAR_ITERM2_PYTHON`: Python 3 executable with the `iterm2` package for
  the experimental iTerm2 backend.

### Intent configuration

To select a model and effort by task intent, create
`<FAMILIAR_HOME>/config/intent.conf` (or
`~/.familiar/config/intent.conf` when `FAMILIAR_HOME` is unset).
Each non-comment entry configures one harness and intent with one model-effort
pair:

```ini
# <harness>.<intent> = <model> <effort>
codex.planning = my-planning-model medium
claude.review = my-review-model high
antigravity.implementation = my-implementation-model low
```

The harness key matches the name passed to `--harness`, including `antigravity`
and `opencode`. Valid intents are `planning`, `implementation`, and `review`.
Either value may be `default`, which leaves that setting to the selected
harness. OpenCode supports a model override, but its TUI does not support a
launch-time effort override, so its entries use `default` for effort:

```ini
opencode.planning = provider/my-model default
```

Without a matching entry, both values come from the harness. Unknown
harnesses, duplicate entries, and malformed lines make the defaults lookup
fail.

`scripts/defaults.sh --harness <harness> --intent <intent>` reports the
resolved model and effort, whether the file exists, every missing intent for
the selected harness, and the file's absolute path. A missing requested entry
uses the target harness's configured defaults. After the summon, the summoning
agent offers to create the file or add all missing entries with you while the
Familiar works. Your choices apply to later summons.

## Requirements

The tmux backend requires Bash, tmux, GNU core utilities, and the selected
harness CLI (`codex`, `claude`, `opencode`, or `agy`) on `PATH`.

The iTerm2 backend is experimental and has not been tested on a Mac. It
requires a local logged-in macOS iTerm2 session, Bash 4.3 or newer, GNU
coreutils `realpath` and `mv` on `PATH` (put the Homebrew `gnubin` directory
first), and a Python 3 executable with the `iterm2` package.
Enable iTerm2's Python API and grant the external script Automation permission.
Set `FAMILIAR_ITERM2_PYTHON` if that Python executable is not `python3`.
Automatic selection uses tmux whenever `TMUX` is set, even inside iTerm2; it
uses iTerm2 only in a direct iTerm2 session. `FAMILIAR_BACKEND` can override
automatic selection, subject to the selected backend context check. The iTerm2
backend cannot run from inside tmux. Its managed record lives on the invoking
iTerm2 session. During launch, a recovery journal under
`FAMILIAR_HOME/recovery` blocks another launch if target cleanup fails. Keep
the promoted request and use `dismiss.sh` from the same origin session to close
the recorded target before retrying. The session record is not guaranteed
across app restart. Live Mac validation is still required before relying on
this backend:
confirm `ITERM_SESSION_ID` maps to the Python session ID, split profile startup
and working directory, close-on-end lookup, and Automation permissions.
