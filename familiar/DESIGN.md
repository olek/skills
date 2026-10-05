# Familiar agent design

A Familiar agent is a single, visible, interactive agent beside the Summoner
terminal. Its terminal lets the user supervise, guide, and dismiss it. It
supports multiple harnesses and lets the user choose a different harness,
model, and effort level from the Summoner agent.

## Inspiration

The workflow draws on the pair programming idea from Extreme Programming,
encouraging a short feedback cycle between a human and an agent. The language of
summoning and familiars borrows from Diana Wynne Jones's fiction, where magical
companions have their own judgment and are often smarter than their summoners.

## Goals

- One Familiar at a time per summoning agent instance.
- A visible native TUI for direct conversation and course correction.
- A self-contained request extracted from the Summoner's context to keep the
  Familiar focused.
- Durable request and response files that serve as input and output for the
  Familiar agent and can be referred to later.
- Independent harness/model/effort choices for the Summoner and Familiar.
- Shallow integration with harness CLIs and terminal APIs, without a daemon.

## Boundaries

The Summoner generates the request and reads the result. The Familiar owns
project updates and writes the response. Durable files carry the handoff
information. The shared paths module owns filenames and locations. Harness
definitions own CLI flags and process environment. Terminal backends own live
Familiar terminals and their management metadata. These boundaries let a new
harness or terminal backend join without changing the request and response
contract.

## Non-goals

Familiar is not a swarm or team of agents. It delegates only read-only research
work to headless helpers; every project update stays with the visible Familiar.
Familiar can never be headless or hide; it is always in plain sight.
