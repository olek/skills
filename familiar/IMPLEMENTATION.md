# Familiar: implementation notes

The concrete mechanics behind [DESIGN.md](DESIGN.md): the scripts, naming
scheme, terminal backend metadata, and catalogs. SKILL.md is the
operational source of truth; correct this file when they disagree.

## Components

Terminal backends provide the pane operations; the scripts are small and
single-purpose. tmux is established. iTerm2 is experimental and has not been
tested on a Mac:

- **`scripts/paths.sh`** - source of truth for the Familiar home,
  antechamber, `YYMMDD-HHMM` naming, bare-name validation, and
  session/request/response path derivation. Sourced by the other scripts or
  queried directly. Its `--request-path` query also creates the antechamber
  directory, so the caller writes the returned path without preparing a
  directory. `FAMILIAR_HOME` is the environment override.
- **`scripts/summon.sh`** - validates name and inputs, captures the local
  time to the minute, promotes the staged request to its durable path, derives the
  response path, enforces one Familiar per summoning agent, and opens the harness
  pane. On launch failure it restores the staged request after verified cleanup;
  an iTerm2 rollback failure preserves the promoted request for recovery.
- **`scripts/message.sh`** - validates one message, resolves the live
  managed Familiar associated with the current summoning session from backend
  metadata, sends the text, waits a fixed 100 ms, and sends Enter separately.
  It never waits for delivery or changes request, response, or completion state.
- **`scripts/dismiss.sh`** - resolves exactly one live managed Familiar
  for the current summoning session and closes it. It accepts no target ID and
  rejects zero, closed-only, or multiple live matches.
- **`scripts/lib/familiar.sh`** - transport-neutral managed-record lookup,
  single-live-target resolution, and scoped close policy.
- **`scripts/lib/backend.sh`** - selects tmux when `TMUX` is set, then iTerm2
  when `ITERM_SESSION_ID` is set, and fails clearly when neither is available.
  `FAMILIAR_BACKEND` can request a specific backend, subject to its context check.
- **`scripts/lib/backends/tmux.sh`** - established tmux implementation.
- **`scripts/lib/backends/iterm2.sh`** and **`iterm2-bridge.py`** - experimental
  one-shot Python API adapter. It resolves the inherited origin ID exactly,
  splits with startup profile settings, and stores a managed record on the
  origin session. This path has fake API tests only; it is untested on a Mac.
- **`scripts/lib/harness.sh`** - source-only module that discovers
  harness definitions by scanning `scripts/lib/harnesses/*.sh` (no central list),
  loads the selected definition, and provides the shell-quoting helper.
- **`scripts/lib/harnesses/*.sh`** - source-only definition per harness using a
  shared generic interface: executable, embedded models and efforts, built-in
  intent suggestions, and pane-command builder, per the contract in
  `scripts/lib/harnesses/README.md`. Add a harness by dropping in one file.
- **`scripts/status.sh`** - finds the current agent's Familiar, derives
  paths from backend metadata, and reports name, harness, target, paths, and
  delivery state. `--wait` polls quietly until delivery or failure; `--auto-dismiss`
  extends that one invocation (see below).
- **`scripts/models.sh`** - prints only model IDs, one per line.
- **`scripts/efforts.sh`** - prints only supported effort IDs, one per
  line.
- **`scripts/defaults.sh`** - prints exactly one named default pair for
  a harness and intent as `model=<id>` and `effort=<id>`, first consulting the
  user-owned intent override file.
- **`scripts/lib/intent-overrides.sh`** - reads the declarative
  `config/intent-overrides.conf` file without evaluating it as shell code.
- Each harness owns its catalogs and may embed them or query its CLI when
  availability depends on local configuration.
- **`tests/test-runner.sh`** - runs the shell test suite. Shared fixtures and
  fakes live in `tests/lib/`; focused lifecycle, harness, path, summon, message,
  dismissal, and status tests live in `tests/cases/`. The suite uses fake tmux
  and harness executables on `PATH` and never touches a real tmux server.
  `tests/cases/iterm2.sh` uses a persistent fake iTerm2 Python API.

## Naming and storage

The caller supplies a lowercase kebab-case name (e.g.
`simplify-familiar-protocol`) that cannot start with an `fm`, `rq`, or `rs`
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
| request | `YYMMDD-HHMM-rq-<name>.md` |
| response | `YYMMDD-HHMM-rs-<name>.md` |

The Familiar home contains a `summonings` child for durable files and an
`antechamber` child for staged requests. Its `config` child holds user-owned
configuration such as `intent-overrides.conf`. `FAMILIAR_HOME` overrides the
default home with an absolute directory. Existing durable request or response
paths are hard failures, including a same-name summon within the same minute;
the staged request stays available for recovery. Deriving every path from the
shared script, rather than trusting caller-supplied paths, avoids mismatches and
stale paths.

The shared layout initializer creates the three child directories when a request
is prepared, intent defaults are resolved, or a summon launches. It does not
create an override file.

## Completion contract

The launcher injects a fixed prompt into the Familiar: read the request, stay in
scope, write the complete result once to the derived response path when done, and
announce completion in the terminal pane. The response path is never placed in the request
itself. That single durable write keeps the result decoupled from the live pane.

## Harness and model policy

`--harness` is required and has no default: the launcher runs as a plain script
and cannot infer its caller. The summoning agent supplies the harness it runs in,
and the user may override it. `--model` is optional and opaque, passed through
unchanged; a user-specified model always wins, and model names are never
translated between vendors. When no model is named, an intent - planning,
implementation, or review - maps to a complete model-effort pair returned by
`defaults.sh`. A user-owned `<FAMILIAR_HOME>/config/intent-overrides.conf` entry
takes precedence over the harness definition's built-in pair. The file uses one
strictly parsed entry per pair: `<harness>.<intent> = <model> <effort>`.

## Backend metadata

The tmux adapter tags the pane with options that the status script reads - the
pane is the tmux record:

| Option | Meaning |
| --- | --- |
| `@familiar` | `1` marks a managed Familiar pane |
| `@familiar_name` | caller-supplied bare name |
| `@familiar_timestamp` | `YYMMDD-HHMM` launch timestamp |
| `@familiar_harness` | selected harness name |
| `@familiar_home` | canonical Familiar home for the launch |
| `@familiar_summoner_pane` | pane ID of the summoning agent |

Request and response options are intentionally absent: the timestamp and home
derive them even after midnight or when `FAMILIAR_HOME` differs in a later
process. The summoner pane ID bounds the singleton and status lookup to the main
harness instance, following it across tmux windows. A pane missing harness
metadata is reported as `unknown`.

The experimental iTerm2 adapter stores name, timestamp, harness, canonical
Familiar home, origin ID, and target ID in a variable on the invoking session.
The target ID is resolved through the API for closed status. This record is not
guaranteed across iTerm2 restart. Exact origin mapping, startup settings, and
closed-target lookup still require live Mac validation.

## Session naming

The session name `YYMMDD-HHMM-fm-<name>` is the canonical identifier. The launcher
passes it to Claude's `--name`; Codex has no launch-time naming flag, so a Codex
Familiar keeps its default session identifier while its name and timestamp stay on
the pane for status.

The launcher also sets `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` for every Claude
Familiar process so tmux and terminal scrollback survive. It is scoped to that
process and does not touch the user's global Claude TUI preference.

## Auto-dismiss inspection

`dismiss.sh` is the public action for immediate dismissal. It resolves
the current summoner's one live managed Familiar and never accepts an arbitrary
pane target. `--wait` alone is a plain completion wait. `--wait --auto-dismiss`
remains a status convenience: after delivery it keeps that invocation alive for
an inspection interval - 60 seconds by default, configurable via
`FAMILIAR_AUTO_DISMISS_SECONDS` up to 60 - then dismisses a remaining live scoped pane,
returning early if none remains. `--auto-dismiss` takes no value and requires an
explicit `--wait`. Handling it in one invocation avoids repeated status probes.
