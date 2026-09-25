# Familiar: design goals and architecture

This document explains why the Familiar skill is built the way it is. To use the
plugin, see [README.md](README.md); for how the agent drives it, see
[SKILL.md](SKILL.md); for the concrete mechanics - scripts, naming scheme, pane
options - see [IMPLEMENTATION.md](IMPLEMENTATION.md). When usage and rationale
disagree, SKILL.md is the operational source of truth and this file should be
corrected.

## What a Familiar is

A Familiar is one visible, interactive agent in a terminal pane beside its
summoning agent. tmux is the established backend; iTerm2 support is experimental
and has not been tested on a Mac. You can watch, guide, interrupt, and dismiss
it - the opposite of a headless agent fleet. "Summon the Familiar" is the intended language for starting
one.

## Inspiration

The way of *working* comes from pair programming and Extreme Programming: a human
and an agent work side by side in a tight feedback loop instead of handing work
over a wall. The *language* - familiars, summoning, dismissing - borrows from the
fiction of Diana Wynne Jones, whose magical companions are rarely passive pets:
they are opinionated, independent, and often smarter than the wizards they serve.

## Design goals

1. **Singular, not a swarm.** Each summoning agent instance manages one Familiar
   at a time.
2. **Visible and interactive by default.** The Familiar runs its native TUI in a
   terminal pane, so you can read its reasoning, correct it mid-task, and answer its
   questions.
3. **Tight feedback loop.** Pair programming and XP, not waterfall.
4. **Context management.** Offloading a self-contained task keeps the summoning
   agent's context focused, and the request and response files leave a durable
   record of the work.
5. **Mix and match harnesses and models.** Summoning agent and Familiar are
   decoupled: a Codex session can summon a Claude Familiar and vice versa, picking
   the best engine and effort for the job.
6. **Shallow integration.** The skill is a thin shell wrapper over a terminal
   backend, the harness CLIs, and a couple of files on disk. It does not need intricate
   integration with the harnesses and has no daemon.

## Architecture

The terminal backend owns the live target and its management metadata. tmux
tags the Familiar pane with options; iTerm2 stores a managed record on the exact
invoking session. The iTerm2 origin mapping and closed-session behavior still
need live Mac validation. Automatic selection chooses tmux whenever `TMUX` is
set, including tmux inside iTerm2. It chooses iTerm2 only for a direct iTerm2
session and fails if neither backend is available.

The summoning agent and Familiar communicate through durable request and response
files. A shared paths script derives their names and locations. The launcher
promotes the staged request and opens a visible pane. Per-harness behavior lives
in definition files discovered from a directory, independently of the terminal
backend. iTerm2 support remains experimental and untested on a Mac.

## Non-goals

- **Not a swarm orchestrator.** No fan-out, no work queues, no many-at-once.
- **The Familiar does its own editing.** It may ask headless sub-agents for
  read-only help such as searching or analysis, but it makes every file change
  itself and never delegates writes.

Backend requirements and the iTerm2 validation gate are listed in
[README.md](README.md).
