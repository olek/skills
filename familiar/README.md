# Familiar

A Familiar is one named, interactive agent that runs in its own tmux pane beside
the session that summoned it. Unlike a headless sub-agent, you watch it reason,
correct it mid-task, answer its questions, and dismiss it - one companion at a
time, in view and in conversation.

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
harness, but you can name `codex`, `claude`, `opencode`, or `antigravity` and pick
the model and reasoning effort supported by that harness. Explicit model and
effort values are passed through unchanged and are not validated against the
informational catalogs or translated between vendors.

## Working with the pane

The Familiar runs its native TUI in a real pane, not a log. Read along, type
corrections, and answer its prompts directly. When it finishes it writes the
complete result to a response file and says so in the pane. It makes every file
change itself and inherits the permission defaults configured locally for its
harness; it may hand read-only lookups to cheaper headless helpers.

The public wrappers are `scripts/summon.sh` for launching,
`scripts/status.sh` for delivery state, `scripts/message.sh` for follow-ups,
and `scripts/dismiss.sh` for dismissal. The follow-up and dismissal
wrappers resolve the managed pane from tmux metadata, so they do not accept an
arbitrary pane target.

Check delivery with `scripts/status.sh`. To wait for completion, invoke
`scripts/status.sh --wait` once; add `--auto-close` to close a remaining live
pane after its inspection interval.

Send a follow-up with `scripts/message.sh --message '<text>'`. It
requires exactly one live managed Familiar for the current summoning pane.

Dismiss that Familiar with `scripts/dismiss.sh`. It accepts no pane ID
and rejects zero, closed-only, or multiple live matches.

## Spotting the session

A Claude Familiar launches with a readable session name (`YYMMDD-HHMM-fm-<name>`),
so the session picker, window title, and status line show a label instead of a
UUID. Codex has no launch-time naming flag, so a Codex Familiar keeps its default
identifier unless you rename it from its TUI.

## Where things live

Requests and responses are durable files under the Familiar home. Before launch,
your request waits briefly in the `antechamber` subdirectory under an
untimestamped name; at summon time it is promoted to a timestamped path so
same-day artifacts sort chronologically:

| File | Name |
| --- | --- |
| request | `YYMMDD-HHMM-fmrq-<name>.md` |
| response | `YYMMDD-HHMM-fmrs-<name>.md` |

## Configuration

| Variable | Effect |
| --- | --- |
| `FAMILIAR_HOME` | Absolute directory for the Familiar home, where requests, responses, and the antechamber live. Overrides the built-in default. |
| `FAMILIAR_AUTO_CLOSE_SECONDS` | Seconds a delivered pane stays open for inspection before it auto-closes, up to 60 (the default). |

## Requirements

Modern Linux with Bash, tmux, GNU core utilities, and the selected harness CLI
(`codex`, `claude`, `opencode`, or `agy`) on `PATH`. macOS and Windows are
currently untested.
