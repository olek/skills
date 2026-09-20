# Skills

Personal, harness-agnostic skills for agentic coding assistants (Claude Code and
Codex). Each subdirectory is a self-contained skill with its own `SKILL.md`.

Skills are meant to be linked into a harness's skills directory rather than
copied, so a single canonical checkout stays the source of truth:

```bash
ln -sfn "$PWD/familiar" ~/.claude/skills/familiar
ln -sfn "$PWD/familiar" ~/.codex/skills/familiar
```

## Skills

- **[familiar](familiar/SKILL.md)**: Summon a single named, interactive Familiar
  (Codex or Claude) into a visible tmux pane beside the pane that requested it.
  One companion at a time, in view and in conversation: for pairing and
  context-offloading, not fire-and-forget swarms. The orchestrator and the
  Familiar can run different harnesses and models, so you pick the best engine for
  the job. See its [design notes](familiar/DESIGN.md) for the rationale.

## License

MIT: do whatever you like, keep the copyright notice. See the [`LICENSE`](LICENSE)
file at the repository root; it covers every skill here.
