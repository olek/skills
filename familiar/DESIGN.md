# Familiar: design goals and architecture

This document explains why the Familiar skill is built the way it is. To use the
plugin, see [README.md](README.md); for how the agent drives it, see
[SKILL.md](SKILL.md); for the concrete mechanics - scripts, naming scheme, pane
options - see [IMPLEMENTATION.md](IMPLEMENTATION.md). When usage and rationale
disagree, SKILL.md is the operational source of truth and this file should be
corrected.

## What a Familiar is

A Familiar is one visible, interactive agent in a tmux pane beside its summoning
agent. You can watch, guide, interrupt, and dismiss it - the opposite of a
headless agent fleet. "Summon the Familiar" is the intended language for starting
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
   tmux pane, so you can read its reasoning, correct it mid-task, and answer its
   questions.
3. **Tight feedback loop.** Pair programming and XP, not waterfall.
4. **Context management.** Offloading a self-contained task keeps the summoning
   agent's context focused, and the request and response files leave a durable
   record of the work.
5. **Mix and match harnesses and models.** Summoning agent and Familiar are
   decoupled: a Codex session can summon a Claude Familiar and vice versa, picking
   the best engine and effort for the job.
6. **Shallow integration.** The skill is a thin shell wrapper over tmux, the
   harness CLIs, and couple files on disk. It does not need intricate
   integration with the harnesses and has no daemon.

## Architecture

The skill is stateless: the Familiar's tmux pane is the only record, tagged with
options that let the status script rediscover it and reconstruct its paths. The
summoning agent and Familiar communicate through two durable files - a request
and a response - a low-bandwidth interface decoupled from the live pane. A shared
paths script owns all naming and storage, so every path is derived one way rather
than passed around. A launcher promotes the staged request, opens the pane, and
injects the Familiar's prompt. Per-harness behavior lives in self-contained
definition files discovered from a directory, so adding a harness is dropping in
one file. The summoning agent and Familiar are otherwise decoupled: the harness
and model are chosen per summon (goal 5).

## Non-goals

- **Not a swarm orchestrator.** No fan-out, no work queues, no many-at-once.
- **The Familiar does its own editing.** It may ask headless sub-agents for
  read-only help such as searching or analysis, but it makes every file change
  itself and never delegates writes.

Runtime requirements (Linux, Bash, tmux, GNU core utilities, a harness CLI on
`PATH`) are listed in [README.md](README.md).
