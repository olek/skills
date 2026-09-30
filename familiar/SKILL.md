---
name: familiar
description: >-
  Summon a named Codex or Claude Code Familiar in a visible terminal pane when
  the user explicitly requests a named familiar, sidekick, companion, or
  sub-agent, or says "summon the Familiar".
---

# Familiar

A Familiar is one named, interactive agent in its own visible terminal pane
beside the session that summoned it: you summon it, watch it, talk to it, and
dismiss it, one companion at a time.

Use this skill when the user asks to create, summon, launch, assign, follow up
with, or check a named Familiar, sidekick, companion, or sub-agent, or says
"summon the Familiar". Headless sub-agents still cover internal parallel work
the user did not request as a named agent.

> **Voice.** Say "Summoning the Familiar...", "at work on...", "has delivered",
> "Dismissing the Familiar", not creating/starting/killing an agent. The idiom
> borrows from the magic of Diana Wynne Jones.

## Write the request

A Familiar works from a self-contained request needing no conversation history
or follow-up. Cover:

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
request_path=$(<skill-dir>/scripts/paths.sh \
  --request-path --name <bare-familiar-name>)
```

If that path already exists, stop and report it as a staging collision; do not
overwrite, rename, or reuse it. Otherwise write the request there. Do not put
the response path or completion contract in the request; the launcher injects
those.

End the request with the target harness, effective model, and effective effort,
each marked specified or inferred. For an omitted override, write `Harness
configured default; no launcher override`.

## Terminal backend

tmux is the established backend. iTerm2 support is experimental and has not
been tested on a Mac. Automatic selection uses tmux whenever `TMUX` is set,
even if tmux runs inside iTerm2. It uses iTerm2 only in a direct iTerm2 session.
If neither is available, the scripts fail with a terminal-backend error. Do not
claim iTerm2 works until the Mac validation gates in [README.md](README.md)
pass.

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

Report the printed terminal target ID and paths. Keep the Familiar interactive
and visible.
The Familiar writes its complete result to the response path and announces
completion in its terminal pane when done.

## Harness and model policy

`--model` is opaque, passed unchanged to the harness CLI. User-specified model
and effort values always win, and model names are never translated between
vendors. If the user specifies either value, pass only the values they named;
leave the other setting to the harness.

When the user names neither value, pick the intent (planning, implementation,
or review) and query the user's Familiar intent configuration:

```bash
<skill-dir>/scripts/defaults.sh --harness <harness> \
  --intent <planning|implementation|review>
```

Use its `model=<id>` and `effort=<id>` pair together. Without a matching
configuration entry, both fields are `default`, so the target harness chooses
them. Omit the corresponding `--model` or `--effort` launcher option for any
`default` field; never pass `default` as its value. A user-specified model
or effort bypasses the intent pair.

If `missing_intents` is nonempty, summon with the resolved pair, then report
the terminal target and paths. Offer to configure every missing intent for the
selected harness while the Familiar works. If `configuration=missing`, offer
to create the file at `configuration_path`; otherwise offer to add the missing
entries there. Ask which model-effort choices the user wants for the listed
intents before writing anything, and preserve existing entries. New choices
apply to later summons. Make this offer once per harness per conversation.

## Interactions with active Familiar agent

```bash
<skill-dir>/scripts/status.sh
```

Reports the Familiar tied to the current summoning agent - its harness,
terminal target, request and response paths, and delivery state - with no
identifier needed.

After summoning, if nothing follows up, do nothing. To wait for completion,
invoke `status.sh --wait` once and wait for its result. Add
`--auto-dismiss` when you want that wait to dismiss a remaining live pane after
its inspection interval; omit it to leave the pane open for the user. Do not
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
