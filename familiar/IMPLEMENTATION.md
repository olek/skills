# Familiar: implementation notes

The concrete mechanics behind [DESIGN.md](DESIGN.md): the scripts, the naming
scheme, pane options, and the catalogs. SKILL.md is the operational source of
truth; correct this file when they disagree.

## Components

tmux is the substrate; the scripts are small and single-purpose:

- **`scripts/familiar-paths.sh`** - source of truth for the Familiar home,
  antechamber, `YYMMDD-HHMM` naming, bare-name validation, and
  session/request/response path derivation. Sourced by the other scripts or
  queried directly. Its `--request-path` query also creates the antechamber
  directory, so the caller writes the returned path without preparing a
  directory. `FAMILIAR_HOME` is the environment override.
- **`scripts/summon-familiar.sh`** - validates name and inputs, captures the local
  time to the minute, promotes the staged request to its durable path, derives the
  response path, enforces one Familiar per summoning agent, and opens the harness
  pane. On pane or metadata failure it closes the partial pane and restores the
  staged request when possible.
- **`scripts/familiar-harness.sh`** - discovers harness definitions by scanning
  `harnesses/*.sh` (no central list), sources them, dispatches shared launcher
  operations, and provides the shell-quoting helper.
- **`scripts/harnesses/*.sh`** - one self-contained, namespaced definition per
  harness: executable, embedded models and efforts, session-name support, effort
  validation, intent suggestions, and pane-command builder, per the contract in
  `scripts/harnesses/README.md`. Add a harness by dropping in one file. `opencode`
  and `antigravity` are planned drop-ins.
- **`scripts/familiar-status.sh`** - finds the current agent's Familiar, derives
  paths from its pane metadata, and reports name, harness, pane, paths, and
  delivery state. `--wait` polls quietly until delivery or failure; `--auto-close`
  extends that one invocation (see below).
- **`scripts/familiar-models.sh`** - prints a definition's embedded models,
  efforts, or intent suggestion. The catalog is hand-maintained, with no runtime
  fetch or cache.
- **`tests/test-familiar.sh`** - exercises the scripts against a fake tmux and fake
  `codex`/`claude` on `PATH`, asserting launch commands, catalog output, harness
  discovery, derived paths, pane metadata, guard failures, and status/wait
  reporting. It never touches a real tmux server.

## Naming and storage

The caller supplies a lowercase kebab-case name (e.g.
`simplify-familiar-protocol`) that cannot start with an `fm`, `fmrq`, or `fmrs`
prefix. The request is first staged, untimestamped, at
`<familiar-home>/antechamber/<name>.md`; the missing timestamp keeps date-like
names unambiguous. An existing staged path is a collision the caller must report
rather than overwrite.

At summon the launcher captures the zero-padded local date and time once, moves
the staged request into durable storage, and derives three names that sort
same-day files chronologically:

| Meaning | Derived value |
| --- | --- |
| session | `YYMMDD-HHMM-fm-<name>` |
| request | `YYMMDD-HHMM-fmrq-<name>.md` |
| response | `YYMMDD-HHMM-fmrs-<name>.md` |

The Familiar home is the parent of both durable files; its `antechamber` child
holds only staged requests. `FAMILIAR_HOME` overrides the default home with an
absolute directory. Existing durable request or response paths are hard failures,
including a same-name summon within the same minute; the staged request stays
available for recovery. Deriving every path from the shared script, rather than
trusting caller-supplied paths, avoids mismatches and stale paths.

## Completion contract

The launcher injects a fixed prompt into the Familiar: read the request, stay in
scope, write the complete result once to the derived response path when done, and
announce completion in the pane. The response path is never placed in the request
itself. That single durable write keeps the result decoupled from the live pane.

## Harness and model policy

`--harness` is required and has no default: the launcher runs as a plain script
and cannot infer its caller. The summoning agent supplies the harness it runs in,
and the user may override it. `--model` is optional and opaque, passed through
unchanged; a user-specified model always wins, and model names are never
translated between vendors. When no model is named, an intent - planning,
implementation, or review - maps to a complete model-effort pair owned by the
harness definition and returned by `familiar-models.sh`.

## Pane metadata

The launcher tags the pane with tmux options that the status script reads, so the
skill stays stateless - the pane is the record:

| Option | Meaning |
| --- | --- |
| `@familiar` | `1` marks a managed Familiar pane |
| `@familiar_name` | caller-supplied bare name |
| `@familiar_timestamp` | `YYMMDD-HHMM` launch timestamp |
| `@familiar_harness` | `codex` or `claude` |
| `@familiar_home` | canonical Familiar home for the launch |
| `@familiar_summoner_pane` | pane ID of the summoning agent |

Request and response options are intentionally absent: the timestamp and home
derive them even after midnight or when `FAMILIAR_HOME` differs in a later
process. The summoner pane ID bounds the singleton and status lookup to the main
harness instance, following it across tmux windows. A pane missing harness
metadata is reported as `unknown`.

## Session naming

The session name `YYMMDD-HHMM-fm-<name>` is the canonical identifier. The launcher
passes it to Claude's `--name`; Codex has no launch-time naming flag, so a Codex
Familiar keeps its default session identifier while its name and timestamp stay on
the pane for status.

The launcher also sets `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` for every Claude
Familiar process so tmux and terminal scrollback survive. It is scoped to that
process and does not touch the user's global Claude TUI preference.

## Auto-close inspection

`--wait` alone is a plain completion wait. `--wait --auto-close` keeps the one
status invocation alive after delivery for an inspection interval - 60 seconds by
default, configurable via `FAMILIAR_AUTO_CLOSE_SECONDS` up to 60 - then closes the
pane if it is still open, returning early if the pane disappears first.
`--auto-close` takes no value and requires an explicit `--wait`. Handling it in
one invocation avoids repeated status probes.
