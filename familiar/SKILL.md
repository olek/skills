---
name: familiar
description: >-
  Summon a named Familiar agent in a visible terminal beside you when the
  user explicitly requests a named familiar, sidekick, companion, or sub-agent,
  or says "summon the Familiar".
---

# Familiar

A Familiar is one named, interactive agent in a visible terminal beside the
summoner terminal. Use this skill only when the user requests a named Familiar,
sidekick, companion, or sub-agent; headless sub-agents still cover internal
parallel work.

## Write the request

Write one self-contained request with an objective, scope, constraints, context
pointers, and acceptance checks. Redact secrets and personal data. Say whether
the Familiar may ask the user questions in its terminal. Use a bare lowercase
kebab-case name, for example `simplify-familiar-protocol`.

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
the harness you run in. The launcher requires `--harness`. User-specified
`--model` and `--effort` values win and are passed unchanged; pass only the
values the user named. Do not translate model names between vendors.

If the user names neither value, choose planning, implementation, or review and
query the intent configuration:

```bash
<skill-dir>/scripts/defaults.sh --harness <harness> --intent <intent>
```

Use the returned model and effort pair; omit an option whose value is `default`.
If `missing_intents` is nonempty, summon first, then offer once per harness per
conversation to configure every missing intent for the selected harness. Ask
for the model and effort choices, then write them to the returned
`configuration_path`, creating it if `configuration=missing` and preserving
existing entries.

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
Do not wait or send progress updates unless the user asks you to stay for its
result, or its result is needed to complete your own assigned work.

`<skill-dir>/scripts/status.sh` reports the current Familiar and delivery state.
If waiting is needed, invoke `status.sh --wait` once with a 12-minute command
timeout and wait quietly. Add `--auto-dismiss` to close a remaining Familiar
terminal after the inspection interval. If the Familiar is still working when
the wait ends, a further wait may be made. Do not poll in a loop.

Send a clarification or follow-up with
`<skill-dir>/scripts/message.sh --message 'text'`.
Dismiss the current Familiar with `<skill-dir>/scripts/dismiss.sh`.

## Terminal backend

tmux is established. iTerm2 is experimental and has not been validated on a
Mac. Selection uses tmux whenever `TMUX` is set; otherwise auto mode uses a
direct iTerm2 session only when `ITERM_SESSION_ID` and `TERM_PROGRAM=iTerm.app`
are both present. Explicit `FAMILIAR_BACKEND=iterm2` permits other callers that
provide a valid session ID. For Codex sandbox access to tmux or iTerm2, see [the
scoped rule example](examples/codex/familiar.rules). The rules allow these
scripts to run but may not grant iTerm2 socket or macOS Automation access; if
the sandbox blocks either, use `danger-full-access` or approve each call.

> **Voice.** Say "Summoning the Familiar...", "at work on...", "has delivered",
> and "Dismissing the Familiar". The idiom borrows from Diana Wynne Jones.
