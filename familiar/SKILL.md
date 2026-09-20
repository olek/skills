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

The `--harness` option selects the Familiar's CLI independently of the summoning
agent's harness, so you can pair the best engine and effort with the task. It
defaults to `codex`, preserving existing launcher callers.

> **Voice.** Prefer the language of summoning over generic agent-speak when
> telling the user what you are doing: "Summoning the Familiar...", "The Familiar
> is at work on ...", "The Familiar has delivered", "Dismissing the Familiar",
> rather than "creating/starting/killing an agent". The idiom borrows from the
> magic of Diana Wynne Jones: familiars, summoning and dismissing.

## Write the request

A Familiar works from a self-contained request that requires no conversation
history or basic follow-up. State a single clear objective in the first line.
Bound the scope explicitly: list what is in and,
where ambiguity is likely, what is out, so the Familiar does not wander into
adjacent work. Name the working directory and any constraints (languages,
frameworks, style rules, files or systems not to touch, time or resource
limits). Give only the context the Familiar actually needs: pointers (file paths,
symbols, prior decisions, links) rather than a full history dump; do not
duplicate content that already lives in a PRD, ADR, ticket, or diff; reference
it instead of re-pasting it. State the intended outcome concretely and include
the acceptance checks the Familiar can self-verify against. Redact secrets,
credentials, and personal data before you hand the request over. If the Familiar
may engage the user directly in its pane rather than only reporting back through
the response file, say so explicitly in the request.

The public Familiar identifier is a bare lowercase kebab-case name such as
`simplify-familiar-protocol`. It must not use an `fm`, `fmrq`, or `fmrs` prefix.
The shared configuration script is the source of truth for the storage
directory and antechamber path. Ask it for the staged request path before
writing the request:

```bash
config=<skill-dir>/scripts/familiar-config.sh
mkdir -p -- "$("$config" --antechamber-directory)"
request_path=$("$config" --request-path --name <bare-familiar-name>)
```

Set `FAMILIAR_HOME` when a different storage directory is needed. The launcher
stores the canonical directory on the Familiar pane, so later status commands
do not need the override.

The staged request path is
`<familiar-home>/antechamber/<bare-familiar-name>.md`. If it already exists, do
not overwrite, rename, or reuse it. Stop the workflow and report the exact path
to the user as a staging collision. Otherwise, write the request there. Do not
put the response filename, response path, or completion-delivery contract in
the request. The launcher injects the resolved response path and the completion
contract into the Familiar's prompt.

Close every request with the target harness, whether it was defaulted or
user-selected, the effective model (or `Claude configured default; no launcher
override`), the effective effort, and whether each value was specified or
inferred.

## Summon

First make sure the task is sufficiently defined and apply the one-Familiar-per-
summoning-agent-instance rule. Here, the summoning agent is the main AI harness
instance that starts the Familiar. Then summon the shared launcher from that
agent's tmux pane. The launcher lives at `scripts/summon-familiar.sh` inside this
skill's directory, typically `~/.claude/skills/familiar/` for Claude Code or
`~/.codex/skills/familiar/` for Codex; use wherever this skill is installed:

```bash
<skill-dir>/scripts/summon-familiar.sh \
  --name <bare-familiar-name> \
  --cwd /absolute/path/to/project \
  [--harness codex|claude] \
  [--model target-harness-model] \
  [--effort target-harness-effort]
```

The launcher captures the zero-padded local date and time through the minute,
moves the staged request from the antechamber to its durable request path, and
derives the session and response names from the same `YYMMDD-HHMM` timestamp and
bare name. It refuses existing durable request or response paths, including a
second same-name summon within one minute. Report the printed pane ID and paths.
Keep the Familiar interactive and visible. Do not use a dangerous permission
bypass or translate model names between vendors.

The launcher gives the Familiar the same contract on either harness: stay within
the request's scope, write the complete result to the resolved response path in a
single write when done, then state completion in the pane (never redirecting
terminal output there). It may hand read-only work to headless sub-agents, often
on a cheaper model, but makes every file change itself.

Claude Familiars set `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` for their process.
This preserves tmux and terminal scrollback without changing the user's global
Claude TUI preference.

A Claude Familiar is launched with `--name` set to the derived session name
`YYMMDD-HHMM-fm-<bare-name>`, so the session picker, window title, and status
line show a readable label instead of a UUID. Codex has no launch-time naming
flag, so a Codex Familiar keeps its default session identifier unless you rename
it from inside its TUI.

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
sub-agents launched outside it. It selects the Familiar associated with the
current summoning agent instance, even if panes move between windows. The report
includes the harness, pane, derived request and response paths, and delivery
state. The canonical Familiar home is retained on the Familiar pane, so status
does not require the original `FAMILIAR_HOME` environment value. A response is either
delivered, awaiting, invalid, or the pane ended without a response. After
summoning, if there is no follow-up activity, do nothing. If the summoning agent
needs to wait for completion and let the user inspect the pane, invoke
`familiar-status.sh --wait --auto-close` once and wait patiently for its result.
The command waits for completion, then keeps the pane open for 60 seconds by
default, returning early if the pane is closed and otherwise closing it when
the inspection interval expires. Set `FAMILIAR_AUTO_CLOSE_SECONDS` to choose a
different interval of up to 60 seconds. `--auto-close` does not take a value.
Ordinary `familiar-status.sh --wait` remains available when automatic closing
is not wanted. Do not repeatedly probe status or perform other frantic
monitoring.

For a follow-up, send the text and press Enter in separate tmux invocations:

```bash
tmux send-keys -t <pane-id> 'follow-up text'
tmux send-keys -t <pane-id> C-m
```

Do not combine the text and `C-m` in one invocation; that can leave the text
unexecuted in the Familiar's prompt.

When the auto-close command reports that the pane closed, leave it closed. When
it reports that it closed the pane after its inspection interval, no manual
dismissal is needed. An explicit request to keep the pane open should omit
`--auto-close`.
