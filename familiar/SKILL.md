---
name: familiar
description: Summon a named Codex or Claude Code Familiar in a visible tmux pane when the user explicitly requests a named familiar, sidekick, companion, or sub-agent, or says "summon the Familiar".
---

# Familiar

A Familiar is a single named, interactive agent summoned into its own visible
tmux pane, beside the pane that requested it. You summon it, watch it work, talk
to it, and dismiss it: one companion at a time, in view and in conversation.

Use this skill when the user asks to create, summon, launch, assign, follow up
with, or check a named Familiar, sidekick, companion, or sub-agent, or when they
say "summon the Familiar". Ordinary headless sub-agents remain available for
internal parallel work the user did not explicitly request as a named agent.

The `--harness` option selects the Familiar's CLI independently of whether Codex or
Claude Code is the orchestrator, so you can pair the best engine and effort with
the job. It defaults to `codex`, preserving existing launcher callers.

> **Voice.** Prefer the language of summoning over generic agent-speak when
> telling the user what you are doing: "Summoning the Familiar…", "The Familiar
> is at work on …", "The Familiar has delivered", "Dismissing the Familiar",
> rather than "creating/starting/killing an agent". The idiom borrows from the
> magic of Diana Wynne Jones: familiars, summoning, and dismissing.

## Write the request

A Familiar works from a *request*, a self-contained brief it can carry out with
zero conversation history, without pinging back for basics. State a single clear
objective in the first line. Bound the scope explicitly: list what is in and,
where ambiguity is likely, what is out, so the Familiar does not wander into
adjacent work. Name the working directory and any constraints (languages,
frameworks, style rules, files or systems not to touch, time or resource
limits). Give only the context the Familiar actually needs: pointers (file paths,
symbols, prior decisions, links) rather than a full history dump; do not
duplicate content that already lives in a PRD, ADR, ticket, or diff; reference
it instead of re-pasting it. State the intended outcome concretely: what "done"
looks like, and any acceptance check the Familiar can self-verify against. Redact
secrets, credentials, and personal data before you hand the request over. If the
Familiar may engage the user directly in its pane rather than only reporting back
through the response file, say so explicitly in the request.

Close every request with the exact response path and a one-line completion
contract: write the complete result there as a single Markdown file, once, only
when the task is finished; no partial or incremental writes, no other channel.
The Familiar treats that file as its sole deliverable back to you.

Record in the request the target harness, whether it was defaulted or
user-selected, the effective model (or `Claude configured default; no launcher
override`), the effective effort, and whether each value was specified or
inferred.

## Where requests and responses live

Start from the session name: `YYMMDD-fm-<slug>`, where `<slug>` is a concise,
activity-specific kebab-case description. The request and response filenames are
that same name with the `fm` tag replaced: `YYMMDD-fmrq-<slug>.md` for the
request and `YYMMDD-fmrs-<slug>.md` for its response. Both live side by side in
one flat directory, `$HOME/.familiar/` (create it if absent), so a request and
its reply sit together. Always pass absolute paths to the launcher, and pick a
response path that does not yet exist.

## Summon

First make sure the task is sufficiently defined and apply the
one-Familiar-per-window rule. Then summon the shared launcher from the
requesting tmux pane. The launcher lives at `scripts/summon-familiar.sh` inside
this skill's own directory, typically `~/.claude/skills/familiar/` when Claude
Code is orchestrating or `~/.codex/skills/familiar/` for Codex; use wherever
this skill is installed:

```bash
<skill-dir>/scripts/summon-familiar.sh \
  --task /absolute/path/to/YYMMDD-fmrq-slug.md \
  --response /absolute/path/to/YYMMDD-fmrs-slug.md \
  --cwd /absolute/path/to/project \
  [--harness codex|claude] \
  [--model target-harness-model] \
  [--effort target-harness-effort]
```

Report the resulting pane ID, request path, and response path. Keep the
Familiar interactive and visible. Do not use a dangerous permission bypass, and
do not translate a model name between vendors.

The launcher gives the Familiar the same contract on either harness: stay within
the request's scope, write the complete Markdown result to the predeclared
response path in a single write when done, then state completion in the pane
(never redirecting terminal output there). It may hand read-only work to headless
sub-agents, often on a cheaper model, but makes every file change itself.

Claude Familiars set `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` for their process.
This preserves tmux and terminal scrollback without changing the user's global
Claude TUI preference.

A Claude Familiar is launched with `--name` set to the session name
`YYMMDD-fm-<slug>`, so the session picker, window title, and status line show a
readable label instead of a UUID. (The launcher recovers that name from the
request filename it is handed.) Codex has no launch-time naming flag, so a Codex
Familiar keeps its default session identifier unless you rename it from inside
its TUI.

## Harness and model policy

`--model` is opaque and is passed unchanged to the selected harness CLI. A
user-specified model always wins. If a user supplies a model without an effort,
do not invent an effort that the selected model may not support.

For a Codex Familiar, when the user does not specify a model, infer the primary
intent and pass the matching model and effort:

- planning, design, or architecture: `gpt-5.6-sol`, `high`;
- implementation or code changes: `gpt-5.6-luna`, `xhigh`;
- review, validation, or verification: `gpt-5.6-sol`, `medium`.

For a Claude Code Familiar, omit `--model` unless the user names a Claude model;
Claude's configured default or managed provider policy chooses the supported
model. With no model override, infer only the matching effort (`high`, `xhigh`,
or `medium`) from the same intent table. If the user supplies effort without a
model, use that effort with the inferred Codex model for a Codex Familiar or with
no model override for a Claude Familiar. Claude accepts `low`, `medium`, `high`,
`xhigh`, and `max` efforts.

## Check status and follow up

When asked whether a managed Familiar exists, run `scripts/familiar-status.sh`
from the same skill directory:

```bash
<skill-dir>/scripts/familiar-status.sh
```

It reports only Familiars managed by this skill, not other native or headless
sub-agents launched outside it. The report includes the Familiar's harness,
pane, request and response paths, and whether the response is delivered,
awaiting, invalid, or the pane ended without a response. Use `--wait` with an
optional `--timeout <seconds>` to wait quietly for delivery or failure.

For a follow-up, send the text and press Enter in separate tmux invocations:

```bash
tmux send-keys -t <pane-id> 'follow-up text'
tmux send-keys -t <pane-id> C-m
```

Do not combine the text and `C-m` in one invocation; that can leave the text
unexecuted in the Familiar's prompt.

After delivery, leave the pane open for 30 seconds for user inspection; then the
user or agent may dismiss it, honoring an explicit request to keep it open.
