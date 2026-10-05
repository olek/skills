# Initial iTerm2 backend validation on macOS

This checklist is for the first validation of the experimental iTerm2 backend
on a Mac. Remove it after that validation is complete.

Run these checks from the skill directory before treating the backend as usable.

1. In Settings > General > Magic, enable the Python API and install the Python
   runtime from iTerm2's Scripts menu. Verify `iterm2` imports with
   `python3 -c 'import iterm2; print(iterm2.__file__)'`, or set
   `FAMILIAR_ITERM2_PYTHON` to that runtime. Familiar checks for the package
   without importing it on each bridge call.
2. Check `bash --version` (4.3 or newer must be first on `PATH`). Check that
   either `realpath` and `mv`, or `grealpath` and `gmv`, report GNU coreutils.
   On a Mac with Bash 3.2 at `/bin/bash`, `/bin/bash scripts/status.sh` should
   print the Bash 4.3 requirement and exit 1.
3. From a plain iTerm2 tab with no tmux, first `cd` to the skill directory.
   Run `bash -c 'source scripts/lib/backends/iterm2.sh && familiar_backend_require_context'`
   three times. Record which app receives the Automation prompt and whether a
   prompt appears on each call.
4. Run `scripts/status.sh`. Expect `No managed Familiar exists`; this checks
   the session lookup and metadata read.
5. Check the launcher cwd, quoting, PATH, and shell environment:

   ```bash
   mkdir -p "$HOME/tmp/it2 o'k \\x"
   bash -c '
     source scripts/lib/harness.sh
     source scripts/lib/backend.sh
     familiar_backend_require_context
     familiar_backend_launch_familiar "${ITERM_SESSION_ID#*:}" "$1" "$2" probe "$(date +%y%m%d-%H%M)" codex "${FAMILIAR_HOME:-$HOME/.familiar}"
   ' familiar-launch "$HOME/tmp/it2 o'k \\x" "/bin/sh -c 'pwd; env | cut -d= -f1 | sort > /tmp/familiar-env-names.txt; sleep 30'"
   scripts/dismiss.sh
   ```

   The pane should show the requested cwd. In a normal iTerm2 tab, run
   `comm -23 <(env | cut -d= -f1 | sort) /tmp/familiar-env-names.txt` to list
   variables missing from the Familiar without writing secret values to disk.
   Check `NODE_EXTRA_CA_CERTS`, `HTTPS_PROXY`, `ANTHROPIC_*`,
   `CLAUDE_CODE_USE_BEDROCK`, `AWS_PROFILE`, `OPENAI_API_KEY`, `CODEX_HOME`,
   `CLAUDE_CONFIG_DIR`, and `FAMILIAR_HOME`.
6. Run `scripts/summon.sh` for Claude and Codex. Run `status.sh`, send a two-line
   message with `message.sh` and confirm one submit, then run `dismiss.sh`.
   Confirm the pane closes and status is clean.
7. From a second tab, run `status.sh` and `dismiss.sh`; neither should see or
   close the first tab's Familiar. Move the summoner tab to another window and
   check status again. Restart iTerm2 and check whether its session metadata
   remains. Enable Broadcast Input and confirm `message.sh` reaches only the
   Familiar.
8. Check the split/launcher race with a stub `codex` that sleeps:

   ```bash
   probe_bin=$(mktemp -d)
   printf '#!/bin/sh\nsleep 60\n' > "$probe_bin/codex"
   chmod +x "$probe_bin/codex"
   (
     set -e
     PATH="$probe_bin:$PATH"
     export PATH
     for name in race-1 race-2 race-3 race-4 race-5 race-6 race-7 race-8 race-9 race-10; do
       scripts/summon.sh --name "$name" --cwd "$PWD" --harness codex
       scripts/status.sh
       scripts/dismiss.sh
     done
   )
   rm -rf "$probe_bin"
   ls /tmp/familiar-launch.* 2>/dev/null
   ```

   Each status should say `awaiting response`; the final `ls` should print
   nothing. Repeat the status and summon checks from Codex with
   `examples/codex/familiar.rules` installed, and from Claude. In each tool
   shell, inspect `env | grep -E '^(TERM_PROGRAM|ITERM_SESSION_ID|TMUX)='` and
   record any socket or Automation denial.
9. Check failure paths with harness stubs that exit 0 and 3. A clean exit should
   close the pane and leave status aborted. A nonzero exit should show the failure
   and wait for Enter while `status.sh` reports
   `aborted without response`; press Enter and check status again. Also disable
   the Python API, quit iTerm2 before running the bridge from another terminal,
   and deny Automation; each error should identify its cause. From Claude with
   its sandbox enabled, check that `/tmp` permits the launcher to be created.
