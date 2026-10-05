---
name: familiar
description: >-
  Summon a single Familiar agent in a visible terminal beside main agent when
  the user explicitly requests a familiar or a familiar agent.
---

# Familiar

A Familiar is a single interactive agent in a visible terminal beside the
summoner terminal. Headless sub-agents still cover internal parallel read-only
work.

## Write the request

Write one self-contained request with an objective, scope, constraints, context
pointers, and acceptance checks. Redact secrets and personal data. Explicitly
allow the Familiar to ask the user questions in its terminal. Use a bare
lowercase kebab-case name for familiar session, for example
`simplify-familiar-protocol`.

```bash
request_path=$(<skill-dir>/scripts/paths.sh --request-path --name <name>)
```

If the path exists, report a staging collision; do not overwrite, rename, or
reuse it. Otherwise write the request there. The launcher injects the response
path and completion contract. End the request with the selected harness, model,
and effort, marked specified or inferred. For an omitted override, write
`Harness configured default; no launcher override`.

## Choose harness, model, and effort

Select the target harness independently of your own. Use the user's choice, or
the harness you run in. The launcher requires `--harness` option. Optional
user-specified `--model` and `--effort` values win and are passed unchanged;
pass only the values the user named.

If the user names neither value, derive planning, implementation, or review
intent and query the model and effort configuration:

```bash
<skill-dir>/scripts/defaults.sh --harness <harness> --intent <intent>
```

Use the returned model and effort pair; omit an option whose value is `default`.
If `missing_intents` is nonempty, summon familiar first, then in summoner agent
offer once per harness per conversation to configure every missing intent for
the selected harness. Ask for the model and effort choices, then write them to
the returned `configuration_path`, creating it if `configuration=missing` and
preserving existing entries.

## Summon

```bash
<skill-dir>/scripts/summon.sh --name <name> --cwd /absolute/project/path \
  --harness codex|claude|opencode|antigravity \
  [--model target-model] [--effort target-effort]
```

Report the printed Familiar terminal ID and paths. Keep the terminal visible.
The Familiar writes its complete result to the response path and announces
completion in its terminal.

## After summoning

Report the Familiar terminal ID and response path, then return control to the
user. The Familiar works independently and announces completion in its terminal.
Do not wait or send progress updates unless familiar result is needed for the
next step.

`<skill-dir>/scripts/status.sh` reports the current Familiar state.  If waiting
is needed, invoke `status.sh --wait` once with a 12-minute command timeout and
wait quietly. Add `--auto-dismiss` to close a remaining Familiar terminal after
the short inspection interval. If the Familiar is still working when the wait
ends, wait again. Do not poll in a quick loop.

Send a clarification or follow-up with
`<skill-dir>/scripts/message.sh --message 'text'`.
Dismiss the current Familiar with `<skill-dir>/scripts/dismiss.sh`.

> **Voice.** Say "Summoning the Familiar...", "at work on...", "has delivered",
> and "Dismissing the Familiar". The idiom borrows from Diana Wynne Jones.
