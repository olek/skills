# Familiar design

A Familiar is one visible, interactive agent beside the summoner terminal. Its
terminal lets the user watch, guide, and dismiss it. tmux is established; iTerm2
is experimental and has not been validated on a Mac.

## Inspiration

The workflow draws on pair programming and Extreme Programming: short feedback
between people and agents. The language of summoning and familiars borrows from
Diana Wynne Jones's fiction, where magical companions have their own judgment.

## Goals

- One Familiar per summoning agent instance.
- A visible native TUI for direct conversation and correction.
- A self-contained request that keeps the summoner's context focused.
- Durable request and response files that outlive either terminal.
- Independent harness choices for the summoner and Familiar.
- Thin integration with harness CLIs and terminal APIs, without a daemon.

## Boundaries

The summoner owns the request and reads the result. The Familiar owns its edits
and writes the response. Durable files carry the handoff. The shared paths
module owns filenames and locations. Harness definitions own CLI flags and
process environment. Terminal backends own live Familiar terminals and their
management metadata. These boundaries let a new harness or terminal backend
join without changing the request and response contract.

## Non-goals

Familiar is not a swarm or queue. It delegates only read-only work to headless
helpers; every file change stays with the visible Familiar.
