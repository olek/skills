# Terminal backend contract

A backend defines these `familiar_backend_*` functions:

```text
require_context
summoner_id
list_familiars <summoner_id>
can_launch <summoner_id>
launch_familiar <summoner_id> <cwd> <command> <name> <timestamp> <harness> <home>
send_literal <familiar_id> <text>
submit <familiar_id>
close_familiar <familiar_id>
display_noun
```

`require_context` and `can_launch` print their own error to stderr and return
nonzero on failure. `familiar_current_summoner_id` is a shared helper in
`backend.sh`, not a backend function.

`list_familiars <summoner_id>` prints one tab-separated row per managed
Familiar: `familiar_id`, `name`, `timestamp`, `harness`, `home`, `closed`.
`closed` is `0` or `1`. `display_noun` prints the terminal noun used in
messages. `launch_familiar` prints the new Familiar ID; `<home>` is canonical.

A launch failure normally returns nonzero after cleaning up the terminal.
Exit status 3 means cleanup failed: the launcher preserves the promoted request
for recovery. The iTerm2 backend owns a journal in `recovery/` and blocks new
launches while recovery is required.

The iTerm2 backend writes a one-shot launcher under `/tmp` and sets the profile
command to `/bin/sh <launcher-path>`. The path is restricted to simple ASCII
characters so iTerm2's profile interpolation and command splitter see only the
shell path and launcher path. The launcher exports the summoner's `PATH`, runs
the requested harness command, removes itself, and waits for Enter after a
nonzero exit. The backend resolves GNU `realpath` and `mv`, including the
Homebrew names `grealpath` and `gmv`, for the shared request promotion flow.
