---
name: familiar
description: Summon a named Codex or Claude Code Familiar in a visible tmux pane when the user explicitly requests a named familiar, sidekick, companion, or sub-agent, or says "summon the Familiar".
---

# Familiar

A Familiar is one named, interactive agent in its own visible tmux pane beside
the pane that summoned it: you summon it, watch it, talk to it, and dismiss it,
one companion at a time.

Use this skill when the user asks to create, summon, launch, assign, follow up
with, or check a named Familiar, sidekick, companion, or sub-agent, or says
"summon the Familiar". Headless sub-agents still cover internal parallel work the
user did not request as a named agent.

> **Voice.** Say "Summoning the Familiar...", "at work on...", "has delivered",
> "Dismissing the Familiar", not creating/starting/killing an agent. The idiom
> borrows from the magic of Diana Wynne Jones.

## Write the request

A Familiar works from a self-contained request needing no conversation history or
follow-up. Cover:

- **Objective**: one clear goal on the first line.
- **Scope**: what is in and, where ambiguous, what is out.
- **Constraints**: working directory, languages, frameworks, style, files or
  systems not to touch, time or resource limits.
- **Context**: only pointers it needs (paths, symbols, prior decisions, links);
  reference a PRD, ADR, ticket, or diff rather than re-pasting it.
- **Outcome**: the concrete result plus acceptance checks it can self-verify.

Redact secrets, credentials, and personal data. If the Familiar may talk to the
user in its pane rather than only reporting through the response file, say so.

The public identifier is a bare lowercase kebab-case name, e.g.
`simplify-familiar-protocol`. Ask the paths script for the staged request path;
do not create any directory yourself:

```bash
request_path=$(<skill-dir>/scripts/paths.sh --request-path --name <bare-familiar-name>)
```

If that path already exists, stop and report it as a staging collision; do not
overwrite, rename, or reuse it. Otherwise write the request there. Do not put the
response path or completion contract in the request; the launcher injects those.

End the request with the target harness, effective model, and effective effort,
each marked specified or inferred. For an omitted override, write `Harness
configured default; no launcher override`.

## Summon

Confirm the task is well defined, then run the launcher. `--harness` selects the
Familiar's CLI independently of your own and is required; unless the user names
one, pass the harness you run in (`claude` or `codex`) - the launcher cannot
infer it.

For Codex sessions whose workspace sandbox cannot access the tmux socket, see
[the scoped rule example](examples/codex/familiar.rules).

```bash
<skill-dir>/scripts/summon.sh \
  --name <bare-familiar-name> \
  --cwd /absolute/path/to/project \
  --harness codex|claude|opencode|antigravity \
  [--model target-harness-model] \
  [--effort target-harness-effort]
```

Report the printed pane ID and paths. Keep the Familiar interactive and visible.
The Familiar writes its complete result to the response path and announces
completion in its pane when done.

## Harness and model policy

`--model` is opaque, passed unchanged to the harness CLI. A user-specified model
always wins, and model names are never translated between vendors. Given a model
without an effort, do not invent one the model may not support.

Query the selected harness catalogs:

```bash
<skill-dir>/scripts/models.sh --harness <harness>
<skill-dir>/scripts/efforts.sh --harness <harness>
<skill-dir>/scripts/defaults.sh --harness <harness> --intent <planning|implementation|review>
```

When the user names no model, pick the intent (planning, implementation, or
review), query `defaults.sh`, and use its named `model=<id>` and
`effort=<id>` pair together. The lookup applies the user's optional Familiar
intent overrides before the built-in recommendations. An intent pair may use
`default` for either field.
Omit the corresponding `--model` or `--effort` launcher option; never pass
`default` as its value.

## Interactions with active Familiar agent

```bash
<skill-dir>/scripts/status.sh
```

Reports the Familiar tied to the current summoning agent - its harness, pane,
request and response paths, and delivery state - so you need not pass an
identifier.

After summoning, if nothing follows up, do nothing. To wait for completion,
invoke `status.sh --wait` once and wait for its result. Add
`--auto-dismiss` when you want that wait to dismiss a remaining live pane after its
inspection interval; omit it to leave the pane open for the user. Do not
repeatedly probe status.

**Important - wait quietly.** After invoking `status.sh --wait`, just set
timeout on the command to 11 minutes and wait for its completion, producing no
intermediate user updates. Do not fidget with sleep loops, timers, repeated
status calls, response-file polling, or short waits that wake up only to
announce that work continues. Let the single blocking command finish.
If agent is still working, then proceed to block on status again.

For a follow-up, use the message script that sends a clarification message to
Familiar agent as a prompt:

```bash
<skill-dir>/scripts/message.sh --message 'follow-up text'
```

To dismiss the current active Familiar, use the dismissal script.

```bash
<skill-dir>/scripts/dismiss.sh
```
