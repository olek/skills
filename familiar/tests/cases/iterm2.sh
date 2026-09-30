# shellcheck shell=bash
# Exercise the public commands against a fake iTerm2 Python API.

run_iterm2() {
  run_with_fakes FAMILIAR_HOME="$OVERRIDE_HOME" TMUX= TMUX_PANE= \
    ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=iterm2 \
    PYTHONPATH="$TEST_ROOT" \
    FAKE_ITERM2_STATE="$TEST_ROOT/iterm2.json" "$@"
}

test_iterm2() {
  cp "$SKILL_ROOT/tests/lib/fake-iterm2.py" "$TEST_ROOT/iterm2.py"
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"

  local output
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
}

test_iterm2_lifecycle() {
  local output launcher_path
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  local -r quoted_cwd="$TEST_ROOT/project's \\(files)"
  mkdir -p -- "$quoted_cwd"
  mkdir -p -- "$TEST_ROOT/login-bin"
  printf 'export FAMILIAR_TEST_LOGIN=loaded\nPATH=%s:$PATH\n' "$(shell_quote "$TEST_ROOT/login-bin")" > "$TEST_HOME/.bash_profile"
  cat > "$FAKE_BIN/codex" <<'SH'
#!/bin/sh
{
  printf 'cwd=%s\n' "$PWD"
  printf 'path=%s\n' "$PATH"
  printf 'login=%s\n' "${FAMILIAR_TEST_LOGIN:-}"
  printf 'debug=%s\n' "${DEBUG-<unset>}"
  printf 'claudecode=%s\n' "${CLAUDECODE-<unset>}"
  for argument do
    printf 'arg=%s\n' "$argument"
  done
} > "${FAKE_CODEX_LOG:-/dev/null}"
exit "${FAKE_CODEX_STATUS:-0}"
SH
  chmod +x "$FAKE_BIN/codex"
  create_request amber "$OVERRIDE_HOME" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name amber --cwd "$quoted_cwd" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-A'
  launcher_path=$(python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['sessions']['target-A']['launcher'])
PY
)
  [[ -f $launcher_path ]] || fail_test 'launcher was removed before the new pane opened it'
  cp -- "$launcher_path" "$TEST_ROOT/launcher.script"
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, awaiting response'
  output=$(run_iterm2 "$MESSAGE" --message $'-first\nsecond\n' 2>&1) || fail_test "$output"
  assert_contains "$output" 'Sent message'
  local summoner_path="$FAKE_BIN:$PATH"
  if output=$(cd -- "$quoted_cwd" && HOME="$TEST_HOME" SHELL=/bin/bash PATH="$summoner_path" \
    FAKE_CODEX_LOG="$TEST_ROOT/codex-launch.log" FAKE_CODEX_STATUS=0 \
    env -u DEBUG -u CLAUDECODE sh "$launcher_path" </dev/null 2>&1); then
    :
  else
    fail_test "launcher failed: $output"
  fi
  [[ ! -e $launcher_path ]] || fail_test 'launcher did not remove itself after it was opened'
  python3 - "$TEST_ROOT/iterm2.json" "$quoted_cwd" "$OVERRIDE_HOME" "$TIMESTAMP" "$summoner_path" "$TEST_ROOT/launcher.script" "$TEST_ROOT/codex-launch.log" <<'PY'
import json, pathlib, shlex, sys
state = json.load(open(sys.argv[1]))
assert state['events'][0][0:4] == ['split', 'origin-A', True, False]
settings = {key: json.loads(value) for key, value in state['events'][0][4].items()}
assert settings['Working Directory'] == sys.argv[2]
assert settings['Command'].startswith('/bin/sh /tmp/familiar-launch.')
assert settings['Custom Command'] == 'Yes'
assert settings['Custom Directory'] == 'Yes'
assert settings['Close Sessions On End'] is True
launcher = pathlib.Path(sys.argv[6]).read_text()
assert launcher.startswith('#!/bin/sh\nrm -f -- "$0"\n')
command_line = shlex.split(launcher.splitlines()[2])
assert command_line[:6] == [
    '${SHELL:-/bin/zsh}', '-l', '-i', '-c',
    'PATH=$1; export PATH; eval "$2"', 'familiar-launch'
]
assert command_line[6] == sys.argv[5]
command = command_line[7]
assert sys.argv[3] in command and sys.argv[4] in launcher and sys.argv[5] in launcher
parts = shlex.split(command)
assert parts[:2] == ['exec', 'codex']
assert parts[parts.index('--cd') + 1] == sys.argv[2]
assert sys.argv[3] + '/summonings/' + sys.argv[4] + '-rq-amber.md' in parts[-1]
launch = pathlib.Path(sys.argv[7]).read_text().splitlines()
assert launch[0] == 'cwd=' + sys.argv[2]
assert launch[1] == 'path=' + sys.argv[5]
assert launch[2] == 'login=loaded'
assert launch[3] == 'debug=<unset>'
assert launch[4] == 'claudecode=<unset>'
actual_args = [line[4:] for line in launch if line.startswith('arg=')]
assert actual_args == parts[2:], (actual_args, parts[2:])
record = json.loads(state['sessions']['origin-A']['variable'])
assert record == dict(summoner='origin-A', familiar='target-A', name='amber', timestamp=sys.argv[4], harness='codex', home=sys.argv[3])
assert state['events'][-2:] == [['send', 'target-A', '-first\nsecond\n', True], ['send', 'target-A', '\r', True]]
PY
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'Dismissed Familiar amber in session target-A'
  output=$(run_iterm2 "$STATUS" --wait --timeout 0 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'

  create_request debug-check "$OVERRIDE_HOME" >/dev/null
  local debug_value="trace \\(backslash)"
  cat > "$FAKE_BIN/claude" <<'SH'
#!/bin/sh
{
  printf 'cwd=%s\n' "$PWD"
  printf 'debug=%s\n' "${DEBUG-<unset>}"
  printf 'claudecode=%s\n' "${CLAUDECODE-<unset>}"
  printf 'alternate_screen=%s\n' "${CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN-<unset>}"
  for argument do
    printf 'arg=%s\n' "$argument"
  done
} > "${FAKE_CODEX_LOG:-/dev/null}"
exit "${FAKE_CODEX_STATUS:-0}"
SH
  chmod +x "$FAKE_BIN/claude"
  output=$(run_iterm2 CLAUDECODE=1 DEBUG="$debug_value" "$LAUNCHER" --name debug-check --cwd "$quoted_cwd" --harness claude 2>&1) || fail_test "$output"
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, awaiting response'
launcher_path=$(python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['sessions']['target-A']['launcher'])
PY
)
  cp -- "$launcher_path" "$TEST_ROOT/claude-launcher.script"
  if output=$(cd -- "$quoted_cwd" && HOME="$TEST_HOME" SHELL=/bin/bash PATH="$summoner_path" \
    FAKE_CODEX_LOG="$TEST_ROOT/claude-launch.log" FAKE_CODEX_STATUS=0 \
    env -u DEBUG -u CLAUDECODE sh "$launcher_path" </dev/null 2>&1); then
    :
  else
    fail_test "Claude launcher failed: $output"
  fi
  [[ ! -e $launcher_path ]] || fail_test 'Claude launcher did not remove itself after it was opened'
  python3 - "$TEST_ROOT/claude-launcher.script" "$debug_value" <<'PY'
import pathlib, shlex, sys
command_line = pathlib.Path(sys.argv[1]).read_text().splitlines()[2]
command = shlex.split(command_line)[7]
parts = shlex.split(command)
assert parts[0] == 'DEBUG=' + sys.argv[2]
assert parts[1:3] == ['CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1', 'exec']
assert parts[3] == 'claude'
PY
  python3 - "$TEST_ROOT/claude-launch.log" "$quoted_cwd" "$debug_value" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
assert lines[:4] == [
    'cwd=' + sys.argv[2],
    'debug=' + sys.argv[3],
    'claudecode=<unset>',
    'alternate_screen=1',
]
PY
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  : > "$FAKE_BIN/codex"
  : > "$FAKE_BIN/claude"
}

test_iterm2_nonzero_exit() {
  local output launcher_path exit_status
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  cat > "$FAKE_BIN/codex" <<'SH'
#!/bin/sh
exit "${FAKE_CODEX_STATUS:-0}"
SH
  chmod +x "$FAKE_BIN/codex"
  create_request failed-exit "$OVERRIDE_HOME" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name failed-exit --cwd "$TEST_ROOT" --harness codex 2>&1) || fail_test "$output"
  launcher_path=$(python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['sessions']['target-A']['launcher'])
PY
)
  [[ -f $launcher_path ]] || fail_test 'launcher was removed before the new pane opened it'
  if (cd -- "$TEST_ROOT" && HOME="$TEST_HOME" SHELL=/bin/bash PATH="$FAKE_BIN:$PATH" \
    FAKE_CODEX_STATUS=3 env -u DEBUG -u CLAUDECODE sh "$launcher_path" </dev/null > "$TEST_ROOT/failed-launch.stdout" 2> "$TEST_ROOT/failed-launch.stderr"); then
    fail_test 'failing harness unexpectedly returned success'
  else
    exit_status=$?
  fi
  [[ $exit_status == 3 ]] || fail_test "launcher returned status $exit_status instead of 3"
  [[ ! -e $launcher_path ]] || fail_test 'failing launcher did not remove itself'
  python3 - "$TEST_ROOT/failed-launch.stdout" <<'PY'
import base64, pathlib, re, sys
output = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r"\x1b]1337;SetUserVar=familiar_exit=([A-Za-z0-9+/=]+)\x07", output)
assert match
assert base64.b64decode(match.group(1)).decode() == "3"
assert "Familiar command failed (status 3); press Enter to close." in output
PY
  run_iterm2 python3 - target-A 3 <<'PY'
import iterm2, sys
iterm2.set_test_variable(sys.argv[1], "user.familiar_exit", int(sys.argv[2]))
PY
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, ended without response'
  output=$(run_iterm2 "$STATUS" --wait --timeout 0 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, ended without response'
  assert_not_contains "$output" 'Timed out'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['sessions']['target-A']['user_variables']['user.familiar_exit'] == 3
PY
  : > "$FAKE_BIN/codex"
}

test_iterm2_failures() {
  local output
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"fail":"split"}\n' > "$TEST_ROOT/iterm2.json"
  create_request cedar "$OVERRIDE_HOME" >/dev/null
  if output=$(run_iterm2 "$LAUNCHER" --name cedar --cwd "$TEST_ROOT" --harness codex 2>&1); then
    fail_test 'split failure unexpectedly succeeded'
  fi
  assert_contains "$output" 'restored the staged request'
  [[ -f $OVERRIDE_ANTECHAMBER/cedar.md ]] || fail_test 'split failure lost staged request'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['events'] == []
assert list(state['sessions']) == ['origin-A', 'origin-B']
PY
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"fail":"metadata"}\n' > "$TEST_ROOT/iterm2.json"
  if output=$(run_iterm2 "$LAUNCHER" --name cedar --cwd "$TEST_ROOT" --harness codex 2>&1); then
    fail_test 'metadata failure unexpectedly succeeded'
  fi
  assert_contains "$output" 'restored the staged request'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert ['close', 'target-A', True] in state['events']
assert 'target-A' not in state['sessions']
PY
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"fail":"metadata-silent"}\n' > "$TEST_ROOT/iterm2.json"
  if output=$(run_iterm2 "$LAUNCHER" --name cedar --cwd "$TEST_ROOT" --harness codex 2>&1); then
    fail_test 'silent metadata failure unexpectedly succeeded'
  fi
  assert_contains "$output" 'iTerm2 did not retain Familiar metadata'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert ['close', 'target-A', True] in state['events']
assert 'target-A' not in state['sessions']
PY
}

test_iterm2_origin_and_retry() {
  local output
  printf '{"sessions":{"origin-A":{"variable":{"summoner":"origin-A","familiar":"target-A","name":"amber","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"origin-B":{"variable":{"summoner":"origin-B","familiar":"target-B","name":"birch","timestamp":"260925-1435","harness":"claude","home":"/tmp/familiar"}},"target-A":{"buried":true},"target-B":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'amber'
  assert_not_contains "$output" 'birch'
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert 'target-B' in state['sessions']
assert 'target-A' not in state['sessions']
assert state['events'] == [['close', 'target-A', True], ['set', 'origin-A', None]]
PY
  if output=$(run_iterm2 ITERM_SESSION_ID=w0t0p0:missing "$STATUS" 2>&1); then
    fail_test 'missing origin unexpectedly succeeded'
  fi
  create_request birch "$OVERRIDE_HOME" >/dev/null
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path))
state['next_target'] = 'target-C'
json.dump(state, open(path, 'w'))
PY
  output=$(run_iterm2 "$LAUNCHER" --name birch --cwd "$TEST_ROOT" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-C'
}


test_iterm2_auto_selection() {
  local output
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 FAMILIAR_BACKEND=auto TMUX=1 TMUX_PANE= "$STATUS" 2>&1) && fail_test 'tmux without pane unexpectedly succeeded'
  assert_contains "$output" 'This command must run from a tmux pane.'
  output=$(run_iterm2 FAMILIAR_BACKEND=auto TMUX=1 TMUX_PANE=%1 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
  output=$(run_iterm2 FAMILIAR_BACKEND=auto TMUX= ITERM_SESSION_ID=w0t0p0:origin-A TERM_PROGRAM=iTerm.app "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
  output=$(run_iterm2 FAMILIAR_BACKEND=iterm2 TMUX= ITERM_SESSION_ID=w0t0p0:origin-A TERM_PROGRAM=VSCode "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
  output=$(run_iterm2 FAMILIAR_BACKEND=auto TMUX= ITERM_SESSION_ID=w0t0p0:origin-A TERM_PROGRAM=VSCode "$STATUS" 2>&1) && fail_test 'inherited iTerm2 session ID selected the backend'
  assert_contains "$output" 'TERM_PROGRAM is not iTerm.app'
}


test_no_terminal_backend() {
  local output
  if output=$(run_iterm2 FAMILIAR_BACKEND=auto ITERM_SESSION_ID= "$STATUS" 2>&1); then
    fail_test 'status unexpectedly succeeded without a terminal backend'
  fi
  assert_contains "$output" 'No supported Familiar terminal backend is available'
}

test_iterm2_list_failure() {
  local output command
  printf '{"sessions":{"origin-A":{"variable":{"summoner":"origin-A","familiar":"target-A","name":"amber","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"target-A":{}},"events":[],"fail":"list"}\n' > "$TEST_ROOT/iterm2.json"
  for command in "$STATUS" "$MESSAGE" "$DISMISS"; do
    if [[ $command == "$MESSAGE" ]]; then
      output=$(run_iterm2 "$command" --message hello 2>&1) && fail_test 'message accepted failed list'
    else
      output=$(run_iterm2 "$command" 2>&1) && fail_test 'command accepted failed list'
    fi
    assert_contains "$output" 'list RPC failed'
    assert_not_contains "$output" 'No managed Familiar'
  done
  output=$(run_iterm2 "$STATUS" --wait --timeout 0 2>&1) && fail_test 'wait accepted failed list'
  assert_contains "$output" 'list RPC failed'
  assert_not_contains "$output" 'No managed Familiar'
}

test_iterm2_orphan_recovery() {
  local output
  printf '{"sessions":{"origin-A":{}},"events":[],"fail":"metadata-close"}\n' > "$TEST_ROOT/iterm2.json"
  create_request willow "$OVERRIDE_HOME" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name willow --cwd "$TEST_ROOT" --harness codex 2>&1) && fail_test 'orphan launch succeeded'
  assert_contains "$output" 'Recovery required for iTerm2 Familiar session target-A'
  [[ -f $OVERRIDE_SUMMONINGS/${TIMESTAMP}-rq-willow.md ]] || fail_test 'promoted request missing'
  [[ ! -f $OVERRIDE_ANTECHAMBER/willow.md ]] || fail_test 'orphan request was restored'
  python3 - "$OVERRIDE_HOME" "$TEST_ROOT/iterm2.json" <<'PY'
import json, pathlib, sys
markers = list((pathlib.Path(sys.argv[1]) / 'recovery').glob('*.json'))
assert len(markers) == 1
record = json.loads(markers[0].read_text())
assert record['summoner'] == 'origin-A' and record['familiar'] == 'target-A'
assert record['name'] == 'willow' and record['home'] == sys.argv[1]
assert 'target-A' in json.load(open(sys.argv[2]))['sessions']
PY
  create_request maple "$OVERRIDE_HOME" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name maple --cwd "$TEST_ROOT" --harness codex 2>&1) && fail_test 'orphan retry succeeded'
  assert_contains "$output" 'needs recovery'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
assert [event[0] for event in json.load(open(sys.argv[1]))['events']].count('split') == 1
PY
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'willow'
  assert_contains "$output" 'session target-A'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
path = sys.argv[1]
state = json.load(open(path))
state.pop('fail')
json.dump(state, open(path, 'w'))
PY
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A'
  output=$(run_iterm2 "$LAUNCHER" --name maple --cwd "$TEST_ROOT" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-A'
}

test_iterm2_failure_nouns() {
  local output failure
  for failure in send submit close; do
    printf '{"sessions":{"origin-A":{"variable":{"summoner":"origin-A","familiar":"target-A","name":"willow","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"target-A":{}},"events":[],"fail":"%s"}\n' "$failure" > "$TEST_ROOT/iterm2.json"
    if [[ $failure == close ]]; then
      output=$(run_iterm2 "$DISMISS" 2>&1) && fail_test 'close failure succeeded'
    else
      output=$(run_iterm2 "$MESSAGE" --message hello 2>&1) && fail_test "$failure failure succeeded"
    fi
    assert_contains "$output" 'session target-A'
    assert_not_contains "$output" 'pane target-A'
  done
  printf '{"sessions":{"origin-A":{"variable":{"summoner":"origin-A","familiar":"target-A","name":"willow","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"target-A":{"exited":true}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 "$MESSAGE" --message hello 2>&1) && fail_test 'send to an exited session succeeded'
  assert_contains "$output" 'SessionNotFound'
}

test_iterm2_selection_and_preflight() {
  local output
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 TMUX=1 "$STATUS" 2>&1) && fail_test 'nested iTerm2 succeeded'
  assert_contains "$output" 'cannot run inside tmux'
  output=$(run_iterm2 ITERM_SESSION_ID=bad:id:extra "$STATUS" 2>&1) && fail_test 'malformed origin succeeded'
  assert_contains "$output" 'valid ITERM_SESSION_ID'
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/realpath"
  chmod +x "$FAKE_BIN/realpath"
  output=$(run_iterm2 "$STATUS" 2>&1) && fail_test 'non-GNU realpath succeeded'
  assert_contains "$output" 'GNU realpath or grealpath'
  rm -- "$FAKE_BIN/realpath"
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/mv"
  chmod +x "$FAKE_BIN/mv"
  output=$(run_iterm2 "$STATUS" 2>&1) && fail_test 'non-GNU mv succeeded'
  assert_contains "$output" 'GNU mv or gmv'
  rm -- "$FAKE_BIN/mv"
  local realpath_binary mv_binary
  realpath_binary=$(type -P realpath)
  mv_binary=$(type -P mv)
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then printf "realpath (GNU coreutils) 9.1\\n"; else printf "grealpath\\n" >> "%s"; exec %s "$@"; fi\n' \
    "$TEST_ROOT/tool-calls" "$(shell_quote "$realpath_binary")" > "$FAKE_BIN/grealpath"
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then printf "mv (GNU coreutils) 9.1\\n"; else printf "gmv\\n" >> "%s"; exec %s "$@"; fi\n' \
    "$TEST_ROOT/tool-calls" "$(shell_quote "$mv_binary")" > "$FAKE_BIN/gmv"
  chmod +x "$FAKE_BIN/grealpath" "$FAKE_BIN/gmv"
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/realpath"
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/mv"
  chmod +x "$FAKE_BIN/realpath" "$FAKE_BIN/mv"
  create_request gnu-tools "$OVERRIDE_HOME" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name gnu-tools --cwd "$TEST_ROOT" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-A'
  assert_file_contains "$TEST_ROOT/tool-calls" 'grealpath'
  assert_file_contains "$TEST_ROOT/tool-calls" 'gmv'
  rm -- "$FAKE_BIN/realpath" "$FAKE_BIN/mv" "$FAKE_BIN/grealpath" "$FAKE_BIN/gmv"
  printf '#!/usr/bin/env bash\nexec python3 -I -S "$@"\n' > "$FAKE_BIN/python-no-iterm2"
  chmod +x "$FAKE_BIN/python-no-iterm2"
  output=$(run_iterm2 FAMILIAR_ITERM2_PYTHON="$FAKE_BIN/python-no-iterm2" "$STATUS" 2>&1) && fail_test 'missing package succeeded'
  assert_contains "$output" 'iTerm2 Python package unavailable'
  for failure in connect 401; do
    printf '{"sessions":{"origin-A":{}},"events":[],"fail":"%s"}\n' "$failure" > "$TEST_ROOT/iterm2.json"
    output=$(run_iterm2 "$STATUS" 2>&1) && fail_test "$failure preflight succeeded"
    if [[ $failure == connect ]]; then
      assert_contains "$output" 'connection failed'
    else
      assert_contains "$output" 'permission denied (401)'
    fi
  done
  for failure in auth-api-disabled auth-not-running auth-tcc-denied auth-old-version auth-error; do
    printf '{"sessions":{"origin-A":{}},"events":[],"fail":"%s"}\n' "$failure" > "$TEST_ROOT/iterm2.json"
    output=$(run_iterm2 "$STATUS" 2>&1) && fail_test "$failure authentication unexpectedly succeeded"
    assert_contains "$output" 'iTerm2 authentication failed'
    case "$failure" in
      auth-api-disabled) assert_contains "$output" 'The Python API is not enabled.' ;;
      auth-not-running) assert_contains "$output" 'iTerm2 not running' ;;
      auth-tcc-denied) assert_contains "$output" 'Not authorized to send Apple events' ;;
      auth-old-version) assert_contains "$output" 'version too old' ;;
      auth-error) assert_contains "$output" 'iTerm2 authentication failed (RuntimeError: AppleScript error text had no trailing error code)' ;;
    esac
  done
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 ITERM2_COOKIE=stale-cookie ITERM2_KEY=stale-key "$STATUS" 2>&1) || fail_test "$output"
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['auth_calls'] == 2
assert state['auth_environment'] == {'cookie': 'fresh-fake-cookie', 'key': 'fresh-fake-key'}
PY
  printf '{"sessions":{"origin-A":{}},"events":[],"fail":"permission"}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 "$STATUS" 2>&1) && fail_test 'sandbox permission failure unexpectedly succeeded'
  assert_contains "$output" 'local sandbox'
  printf '{"sessions":{"origin-A":{}},"events":[],"fail":"406"}\n' > "$TEST_ROOT/iterm2.json"
  if output=$(run_iterm2 "$STATUS" 2> "$TEST_ROOT/bridge.stderr"); then
    fail_test 'old iTerm2 package unexpectedly succeeded'
  fi
  [[ -z $output ]] || fail_test "iTerm2 library text leaked to stdout: $output"
  assert_file_contains "$TEST_ROOT/bridge.stderr" 'package is too old'
}

test_iterm2_fake_contract() {
  local output
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  run_iterm2 python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import asyncio, json, sys
import iterm2

assert iterm2.components_in_shell_command(r"/bin/sh 'a\nb' 'x\ty' 'z\rz' 'q\aq' 'c:\z'") == [
    '/bin/sh', 'a\nb', 'x\ty', 'z\rz', 'q\aq', r'c:\z'
]

async def check():
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_command('exec codex')
    profile.set_close_sessions_on_end(True)
    await iterm2.Session('origin-A').async_split_pane(profile_customizations=profile)

asyncio.run(check())
state = json.load(open(sys.argv[1]))
assert ['exec-failed', 'exec'] in state['events']
assert 'target-A' not in state['sessions']
PY
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
}

test_iterm2_python_discovery() {
  local real_python runtime_root runtime_path output
  real_python=$(type -P python3)
  runtime_root="$TEST_HOME/Library/ApplicationSupport/iTerm2/iterm2env/versions"
  runtime_path="$runtime_root/3.11/bin/python3"
  mkdir -p -- "$runtime_root/3.9/bin" "$runtime_root/3.11/bin"
  printf '#!/bin/sh\nif [ "${1:-}" = "-c" ] && [ "${2:-}" = '\''import importlib.util, sys; sys.exit(importlib.util.find_spec("iterm2") is None)'\'' ]; then exit 1; fi\nprintf "default %%s\\n" "$*" >> "%s"\nexec %s "$@"\n' \
    "$TEST_ROOT/python-calls" "$(shell_quote "$real_python")" > "$FAKE_BIN/python3"
  chmod +x "$FAKE_BIN/python3"
  local runtime
  for runtime in "$runtime_root/3.9/bin/python3" "$runtime_path"; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "$0" "${1:-}" >> "%s"\nexec %s "$@"\n' \
      "$TEST_ROOT/python-calls" "$(shell_quote "$real_python")" > "$runtime"
    chmod +x "$runtime"
  done
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 HOME="$TEST_HOME" FAMILIAR_ITERM2_PYTHON= "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
  assert_file_contains "$TEST_ROOT/python-calls" "$runtime_path $SKILL_ROOT/scripts/lib/backends/iterm2-bridge.py"
  assert_file_not_contains "$TEST_ROOT/python-calls" "$FAKE_BIN/python3 $SKILL_ROOT/scripts/lib/backends/iterm2-bridge.py"
}

test_familiar_iterm2() {
  test_iterm2
  test_iterm2_lifecycle
  test_iterm2_nonzero_exit
  test_iterm2_failures
  test_iterm2_origin_and_retry
  test_iterm2_auto_selection
  test_no_terminal_backend
  test_iterm2_list_failure
  test_iterm2_orphan_recovery
  test_iterm2_failure_nouns
  test_iterm2_selection_and_preflight
  test_iterm2_fake_contract
  test_iterm2_python_discovery
}
