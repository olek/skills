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
