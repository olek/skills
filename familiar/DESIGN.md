# Familiar: design goals and architecture

This document explains *why* the Familiar skill is built the way it is. For
*how* to use it, see [SKILL.md](SKILL.md). When usage and rationale disagree,
SKILL.md is the operational source of truth and this file should be corrected.

## What a Familiar is

A Familiar is a single named, interactive agent summoned into its own visible
tmux pane, beside the pane that requested it. You summon it, watch it work,
talk to it, and dismiss it. It is the deliberate opposite of a fleet of
headless background agents: one companion at a time, in view, in conversation.

"Summon the Familiar" is the intended ritual for starting one.

## Inspiration

Two influences shape this skill. The way of *working* comes from pair
programming and Extreme Programming: a human and an agent side by side in tight
feedback, correcting course as they go, rather than a waterfall hand-off thrown
over a wall. The *language* (familiars, summoning and dismissing) borrows from
the fiction of Diana Wynne Jones, whose magicians keep a single bonded familiar
rather than a swarm.

## Design goals

1. **Singular, not a swarm.** One managed Familiar per tmux window, enforced
   mechanically. The value is a focused collaborator you stay in dialogue with,
   not throughput from piling up isolated agents. The name was chosen to
   reinforce this: a Familiar is bonded and singular, where "minions" invite a
   crowd.

2. **Visible and interactive by default.** The Familiar runs in a real pane with
   its normal TUI, not redirected to a log. You can read its reasoning, correct
   it mid-task, and answer its questions. Alternate-screen mode is disabled for
   Claude Familiars (`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`) so tmux scrollback
   is preserved without changing the user's global preference.

3. **Back-and-forth over the wall.** The model is pair-programming and XP, not
   waterfall hand-off. Human, orchestrator, and Familiar work together; the
   follow-up path (`tmux send-keys`) is a first-class part of the workflow, not
   an afterthought. Fire-and-forget headless delegation still exists for
   internal parallel work, but it is explicitly *not* what this skill is for.

4. **Context management.** Offloading a self-contained task to a Familiar keeps
   the orchestrator's own context window from churning on work that can be
   scoped, delegated, and summarized back through a single response file. The
   request/response file pair is the durable, low-bandwidth interface.

5. **Mix and match harnesses and models.** The orchestrator and the Familiar are
   decoupled: a Codex session can summon a Claude Familiar and vice versa,
   picking the best engine and reasoning effort for the job. `--harness`
   selects the Familiar's CLI independently of who is orchestrating. This is a core
   capability, not a corner case.

6. **Shallow integration, KISS.** The skill is a thin shell wrapper over tmux
   and the two harness CLIs. It stores a little metadata on the Familiar's pane
   and reads it back. It does not wrap, proxy, or reimplement either harness, and it
   holds no long-lived daemon or state of its own. Everything it knows lives on
   the tmux pane and in two files on disk.

## Architecture

Three moving parts, plus tmux as the substrate:

- **`scripts/summon-familiar.sh`**: validates inputs (must run inside tmux,
  absolute paths, known harness, supported effort), enforces the
  one-Familiar-per-window rule, builds the harness-specific launch command, and
  splits a new pane running it. It records identifying metadata on the new pane
  as tmux pane options (see below).

- **`scripts/familiar-status.sh`**: reads that pane metadata back for the
  requesting window and reports each Familiar's name, harness, pane, request and
  response paths, and delivery state (delivered / awaiting / invalid path /
  ended without response). `--wait [--timeout]` polls quietly until delivery or
  failure.

- **`tests/test-familiar.sh`**: exercises both scripts against a fake `tmux`
  (and fake `codex`/`claude`) on `PATH`, asserting the exact launch commands,
  pane metadata, guard failures, and status/wait reporting. It never touches a
  real tmux server.

### Pane metadata

The launcher tags the Familiar's pane with tmux pane options and the status script
reads them. This keeps the skill stateless; the pane *is* the record:

| Option | Meaning |
| --- | --- |
| `@familiar` | `1` marks a pane as a managed Familiar |
| `@familiar_name` | session name, derived from the request filename |
| `@familiar_harness` | `codex` or `claude` |
| `@familiar_task` | absolute path to the request |
| `@familiar_response` | absolute path to the predeclared response file |

Using `TMUX_PANE` (not the active client/window) as the anchor means switching
windows or sessions while a Familiar is being prepared does not misdirect the
split or the status query.

### Session naming

The session name is the canonical identifier: `YYMMDD-fm-<slug>`. The request and
response filenames are formed from it by substituting the `fm` tag with `fmrq`
and `fmrs`, so all three share one base. The launcher is handed the request path
and recovers the name from it, swapping the `fmrq` infix back to `fm` and
folding the result to Claude's `--name` charset (`[A-Za-z0-9_-]`, 64 chars). A
Claude Familiar is launched with `--name`, so that human-friendly label, not a
UUID, shows in the session picker, window title, and status line. Codex exposes
no launch-time naming flag (its session name is only settable via an interactive
TUI rename), so a Codex Familiar keeps its default identifier; the name is still
recorded on the pane for status reporting.

### The completion contract

The launcher hands the Familiar a fixed contract (the prompt in
`scripts/summon-familiar.sh`): stay within scope, write the complete result to the
predeclared response path once when done, and state completion in the pane. That
single write, with no terminal output, leaves the orchestrator a durable artifact
decoupled from the live pane.

### Request and response files

The request and the predeclared response file are the low-bandwidth, durable
interface between orchestrator and Familiar. Their location is not hardwired into
the tooling: the scripts accept any absolute paths. SKILL.md documents the
convention: a single flat directory, `$HOME/.familiar/`, holding both a request
and its reply side by side, told apart by an infix after the date
(`YYMMDD-fmrq-<slug>.md` for the request, `YYMMDD-fmrs-<slug>.md` for the
response). A request states the objective, scope, constraints, working directory,
relevant context, intent, the effective Familiar model and effort (and whether each
was specified or inferred), and the exact response path.

### Harness and model policy

`--model` is opaque and passed through unchanged; a user-specified model always
wins, and model names are never translated between vendors. When the user does
not name a model, intent (planning / implementation / review) maps to a Codex
model + effort, or (for a Claude Familiar) to an effort only, letting Claude's
configured default choose the model. Effort is never invented for a model that
may not support it.

## Non-goals

- **Not a swarm orchestrator.** No fan-out, no work queues, no many-at-once.
- **Not a headless-delegation tool.** If the user didn't ask for a *named*,
  visible Familiar, headless delegation is the right tool instead.
- **Not a harness abstraction layer.** The skill does not paper over Codex vs
  Claude differences beyond selecting the command and the completion contract.
- **No permission bypass, no delegated file changes.** A Familiar keeps ordinary
  approvals and owns every edit and write itself; read-only helpers are fine, but
  modifications never leave it.

## Portability

The skill is intended to run on any machine, not just the maintainer's. The
shell scripts contain no hardcoded home-relative paths; they derive their own
location from `BASH_SOURCE`, take the request/response/working paths as absolute
arguments, and depend only on `tmux` plus the selected harness CLI (`codex` or
`claude`) being on `PATH`. Machine-specific choices (where request files live,
which harness/model to default to) are expressed as documented conventions with
sensible fallbacks rather than as hard requirements, so installing the skill
elsewhere needs no edits.
