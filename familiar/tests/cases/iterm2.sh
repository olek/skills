#!/usr/bin/env bash
# Exercise the public commands against a fake iTerm2 Python API.

run_iterm2() {
  env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" FAMILIAR_HOME="$OVERRIDE_STORAGE" TMUX= TMUX_PANE= ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=iterm2 FAMILIAR_ITERM2_PYTHON=python3 PYTHONPATH="$TEST_ROOT" FAKE_ITERM2_STATE="$TEST_ROOT/iterm2.json" TEST_TIMESTAMP="$TIMESTAMP" "$@"
}

test_iterm2() {
  cp "$SKILL_ROOT/tests/fake-iterm2.py" "$TEST_ROOT/iterm2.py"
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"focused_id":"origin-B"}\n' > "$TEST_ROOT/iterm2.json"

  local output
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
}

# Called separately by the runner after the empty-state slice.
test_iterm2_lifecycle() {
  local output
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"focused_id":"origin-B"}\n' > "$TEST_ROOT/iterm2.json"
  create_request amber "$OVERRIDE_STORAGE" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name amber --cwd "$TEST_ROOT" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-A'
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, awaiting response'
  output=$(run_iterm2 "$MESSAGE" --message $'-first\nsecond\n' 2>&1) || fail_test "$output"
  assert_contains "$output" 'Sent message'
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['events'][0][0:4] == ['split', 'origin-A', True, False]
settings = state['events'][0][4]
assert settings['custom_directory'] == sys.argv[1].rsplit('/', 1)[0]
assert settings['use_custom_command'] == 'Yes'
assert settings['initial_directory_mode'] == 'Yes'
assert settings['close_sessions_on_end'] is True
assert state['events'][-2:] == [['send', 'target-A', '-first\nsecond\n', True], ['send', 'target-A', '\r', True]]
PY
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'Dismissed Familiar amber in session target-A'
  output=$(run_iterm2 "$STATUS" --wait --timeout 0 2>&1) || fail_test "$output"
  assert_contains "$output" 'ended without response'
}

test_iterm2_failures() {
  local output
  printf '{"sessions":{"origin-A":{},"origin-B":{}},"events":[],"fail":"split"}\n' > "$TEST_ROOT/iterm2.json"
  create_request cedar "$OVERRIDE_STORAGE" >/dev/null
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
}

test_iterm2_origin_and_retry() {
  local output
  printf '{"sessions":{"origin-A":{"variable":{"origin":"origin-A","target":"target-A","name":"amber","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"origin-B":{"variable":{"origin":"origin-B","target":"target-B","name":"birch","timestamp":"260925-1435","harness":"claude","home":"/tmp/familiar"}},"target-A":{},"target-B":{}},"events":[],"focused_id":"origin-B"}\n' > "$TEST_ROOT/iterm2.json"
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'amber'
  assert_not_contains "$output" 'birch'
  output=$(run_iterm2 "$DISMISS" 2>&1) || fail_test "$output"
  python3 - "$TEST_ROOT/iterm2.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert 'target-B' in state['sessions']
assert 'target-A' not in state['sessions']
assert state['events'] == [['close', 'target-A', True]]
PY
  if output=$(env PATH="$FAKE_BIN:$PATH" TMUX= ITERM_SESSION_ID=w0t0p0:missing FAMILIAR_BACKEND=iterm2 FAMILIAR_ITERM2_PYTHON=python3 PYTHONPATH="$TEST_ROOT" FAKE_ITERM2_STATE="$TEST_ROOT/iterm2.json" "$STATUS" 2>&1); then
    fail_test 'missing origin unexpectedly succeeded'
  fi
  create_request birch "$OVERRIDE_STORAGE" >/dev/null
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
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" TMUX=1 TMUX_PANE= ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=auto "$STATUS" 2>&1) && fail_test 'tmux without pane unexpectedly succeeded'
  assert_contains "$output" 'This command must run from a tmux pane.'
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" TMUX=1 TMUX_PANE=%1 ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=auto FAKE_TMUX_STATE="$FAKE_TMUX_STATE" FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
}


test_no_terminal_backend() {
  local output
  if output=$(env TMUX= TMUX_PANE= ITERM_SESSION_ID= FAMILIAR_BACKEND=auto "$STATUS" 2>&1); then
    fail_test 'status unexpectedly succeeded without a terminal backend'
  fi
  assert_contains "$output" 'No supported Familiar terminal backend is available'
}
