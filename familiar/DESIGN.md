# Familiar: design goals and architecture

This document explains why the Familiar skill is built the way it is. For how
to use it, see [SKILL.md](SKILL.md). When usage and rationale disagree,
SKILL.md is the operational source of truth and this file should be corrected.

## What a Familiar is

A Familiar is one visible, interactive agent in a tmux pane beside its summoning
agent. You can watch, guide, interrupt, and dismiss it - the opposite of a
headless agent fleet.

"Summon the Familiar" is the intended language for starting one.

## Inspiration

Two influences shape this skill.

The way of *working* comes from pair programming and Extreme Programming: a
human and an agent work side by side, correcting course in a tight feedback
loop instead of handing work over a wall.

The *language* (familiars, summoning and dismissing) borrows from the fiction of
Diana Wynne Jones. Across her work, magical companions are rarely passive pets:
they are opinionated, independent, and often smarter than the witches and
wizards they serve.

## Design goals

1. **Singular, not a swarm.** Each summoning agent instance can manage one
   Familiar. The summoning agent is the main AI harness instance that starts it.

2. **Visible and interactive by default.** The Familiar runs in a real tmux pane
   with its native TUI, not redirected to a log. You can read its reasoning,
   correct it mid-task, and answer its questions.

3. **Tight feedback loop and fast error correction.** The model is
   pair-programming and XP, not waterfall.

4. **Context management.** Offloading a self-contained task to a Familiar keeps
   the summoning agent's context focused. The request and response files are a
   durable, low-bandwidth interface, and each invocation leaves a record of its
   activity.

5. **Mix and match harnesses and models.** The summoning agent and Familiar are
   decoupled: a Codex session can summon a Claude Familiar and vice versa,
   picking the best engine and reasoning effort for the job.

6. **Shallow integration, KISS.** The skill is a thin shell wrapper over tmux,
   the harness CLIs, and two files on disk. It stores only the pane metadata
   needed to identify a Familiar and reconstruct its paths. It does not proxy or
   reimplement the harnesses and has no daemon.

## Structure

Four moving parts, plus tmux as the substrate:

- **`scripts/familiar-config.sh`**: the source of truth for the configured
  Familiar home, antechamber, current `YYMMDD-HHMM` naming convention, bare-name
  validation, and session, request, and response path derivation. It can be
  sourced by the other scripts or queried directly by a summoning agent.
  `FAMILIAR_HOME` is the deterministic environment override.

- **`scripts/summon-familiar.sh`**: validates the bare name and inputs, captures
  the local date and time through the minute, promotes the staged request to its
  durable timestamped path, derives the response path, enforces one Familiar per
  summoning agent instance, and opens a pane running the selected harness. If
  pane creation or metadata setup fails, it closes the partial pane and restores
  the staged request when possible.

- **`scripts/familiar-status.sh`**: finds the Familiar associated with the
  current summoning agent, derives request and response paths from its canonical
  launch metadata, and reports the name, harness, pane, paths, and delivery
  state. `--wait` polls quietly until delivery or failure. Its optional
  `--auto-close` extension keeps the same invocation alive after delivery for an
  inspection interval of 60 seconds by default, then closes the managed pane if
  it remains open. `FAMILIAR_AUTO_CLOSE_SECONDS` can configure the interval.

- **`tests/test-familiar.sh`**: exercises all three scripts against a fake tmux
  and fake `codex`/`claude` on `PATH`, asserting exact launch commands, derived
  paths, reduced pane metadata, guard failures, and status/wait reporting. It
  never touches a real tmux server.

## Naming and storage

The caller supplies a lowercase kebab-case Familiar name, for example
`simplify-familiar-protocol`. The name cannot use an `fm`, `fmrq`, or `fmrs`
prefix. Before launch, the summoning agent writes the request to the staging
path `<familiar-home>/antechamber/<name>.md`. This filename has no timestamp, so
date-like names are unambiguous and allowed. An existing staged path is a
collision: the summoning agent must stop and report it rather than
overwriting, renaming, or guessing.

At summon time, the launcher captures the zero-padded local date, hour, and
minute once, moves the staged request to durable storage, and derives three
related names. The timestamp makes same-day files sort chronologically:

| Meaning | Derived value |
| --- | --- |
| session | `YYMMDD-HHMM-fm-<name>` |
| request | `YYMMDD-HHMM-fmrq-<name>.md` |
| response | `YYMMDD-HHMM-fmrs-<name>.md` |

The configured Familiar home is the parent of both durable files and its
`antechamber` child contains only staged requests. The default home is owned by
`familiar-config.sh`; callers can set `FAMILIAR_HOME` to an absolute directory
for a deterministic override. The request contains no response path or
completion contract. The launcher injects both into the interactive Familiar
prompt. Existing durable request or response paths are hard failures, including
a same-name summon within the same minute, and the staged request remains
available for recovery.

## Pane metadata

The launcher tags the Familiar's pane with tmux pane options and the status
script reads them. This keeps the skill stateless; the pane is the record:

| Option | Meaning |
| --- | --- |
| `@familiar` | `1` marks a pane as a managed Familiar |
| `@familiar_name` | the caller-supplied bare Familiar name |
| `@familiar_timestamp` | the `YYMMDD-HHMM` launch timestamp |
| `@familiar_harness` | `codex` or `claude` |
| `@familiar_home` | canonical Familiar home used for the launch |
| `@familiar_summoner_pane` | pane ID of the summoning agent instance |

The request and response options are intentionally absent. The timestamp and
canonical Familiar home are enough to derive them, even after midnight or when
`FAMILIAR_HOME` differs in a later process. The summoner pane ID gives the
singleton and status lookup a boundary that follows the main harness instance
across tmux windows.

## Session naming

The session name is the canonical identifier `YYMMDD-HHMM-fm-<name>`. The launcher
passes it to Claude's `--name` option. Codex exposes no launch-time naming flag,
so a Codex Familiar keeps its default session identifier; the bare name and
timestamp are still recorded on the pane for status reporting.

## The completion contract

The launcher hands the Familiar a fixed prompt contract: read the request,
stay within scope, write the complete result to the derived response path once
when done, and state completion in the pane. That single write, with no terminal
output redirected into the response, leaves the summoning agent a durable
artifact decoupled from the live pane.

## Completion and auto-close inspection

Ordinary `--wait` remains a simple completion wait. When the summoning agent
needs to wait for completion and give the user time to inspect the visible pane,
it makes one status invocation with `--wait --auto-close`. The status script owns both
the completion polling and the auto-close inspection interval, which defaults to
60 seconds and can be configured by `FAMILIAR_AUTO_CLOSE_SECONDS`. It returns
early if the managed Familiar pane disappears or becomes dead, and closes the
pane automatically if it remains open when the interval expires. `--auto-close`
does not take a value, requires an explicit `--wait`, and its interval must not
exceed 60 seconds.

The summoning agent should avoid repeated manual status probes; `--auto-close` keeps
this behavior inside one status invocation.

## Request and response files

The request and response files are the low-bandwidth, durable interface between
summoning agent and Familiar. Before summoning, the untimestamped request lives
briefly in the antechamber. The launcher chooses the timestamp and moves it into
the durable request path; the temporary filename does not survive that
promotion. All paths come from one shared script rather than being supplied
independently to the launcher. This eliminates midnight mismatches, stale
caller-selected paths, and redundant path metadata while preserving delivery,
wait, and pane-aware auto-close semantics.

## Harness and model policy

`--model` is opaque and passed through unchanged; a user-specified model always
wins, and model names are never translated between vendors. When the user does
not name a model, intent (planning, implementation, or review) maps to a Codex
model and effort, or, for a Claude Familiar, to an effort only so Claude's
configured default chooses the model. Effort is never invented for a model that
may not support it.

## Non-goals

- **Not a swarm orchestrator.** No fan-out, no work queues, no many-at-once.
- **Not a headless-delegation tool.** If the user did not ask for a named,
  visible Familiar, headless delegation is the right tool instead.
- **Not a harness abstraction layer.** The skill does not paper over Codex and
  Claude differences beyond selecting the command and completion contract.
- **No permission bypass, no delegated file changes.** A Familiar keeps ordinary
  approvals and owns every edit and write itself; read-only helpers are fine,
  but modifications never leave it.

## Portability

The skill supports modern Linux with Bash, tmux, GNU core utilities, and the
selected harness CLI (`codex` or `claude`) on `PATH`. The scripts derive their
installation path from `BASH_SOURCE`; storage, harness, model, and effort choices
require no source edits. macOS and Windows are currently untested.
