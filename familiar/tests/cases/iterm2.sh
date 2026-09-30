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
  local -r quoted_cwd="$TEST_ROOT/project's files"
  mkdir -p -- "$quoted_cwd"
  create_request amber "$OVERRIDE_STORAGE" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name amber --cwd "$quoted_cwd" --harness codex 2>&1) || fail_test "$output"
  assert_contains "$output" 'target-A'
  output=$(run_iterm2 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'session target-A, awaiting response'
  output=$(run_iterm2 "$MESSAGE" --message $'-first\nsecond\n' 2>&1) || fail_test "$output"
  assert_contains "$output" 'Sent message'
  python3 - "$TEST_ROOT/iterm2.json" "$quoted_cwd" "$OVERRIDE_STORAGE" "$TIMESTAMP" <<'PY'
import json, shlex, sys
state = json.load(open(sys.argv[1]))
assert state['events'][0][0:4] == ['split', 'origin-A', True, False]
settings = state['events'][0][4]
assert settings['custom_directory'] == sys.argv[2]
assert settings['command'].startswith('exec codex --no-alt-screen ')
parts = shlex.split(settings['command'])
assert parts[parts.index('--cd') + 1] == sys.argv[2]
assert sys.argv[3] + '/summonings/' + sys.argv[4] + '-rq-amber.md' in settings['command']
assert settings['use_custom_command'] == 'Yes'
assert settings['initial_directory_mode'] == 'Yes'
assert settings['close_sessions_on_end'] is True
record = state['sessions']['origin-A']['variable']
assert record == dict(origin='origin-A', target='target-A', name='amber', timestamp=sys.argv[4], harness='codex', home=sys.argv[3])
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
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" TMUX=1 TMUX_PANE=%1 ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=auto FAKE_TMUX_STATE="$FAKE_TMUX_STATE" FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" FAKE_TMUX_AUTO_DISMISS_ENABLED=0 "$STATUS" 2>&1) || fail_test "$output"
  assert_contains "$output" 'No managed Familiar exists'
}


test_no_terminal_backend() {
  local output
  if output=$(env TMUX= TMUX_PANE= ITERM_SESSION_ID= FAMILIAR_BACKEND=auto "$STATUS" 2>&1); then
    fail_test 'status unexpectedly succeeded without a terminal backend'
  fi
  assert_contains "$output" 'No supported Familiar terminal backend is available'
}

test_iterm2_list_failure() {
  local output command
  printf '{"sessions":{"origin-A":{"variable":{"origin":"origin-A","target":"target-A","name":"amber","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"target-A":{}},"events":[],"fail":"list"}\n' > "$TEST_ROOT/iterm2.json"
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
  create_request willow "$OVERRIDE_STORAGE" >/dev/null
  output=$(run_iterm2 "$LAUNCHER" --name willow --cwd "$TEST_ROOT" --harness codex 2>&1) && fail_test 'orphan launch succeeded'
  assert_contains "$output" 'Recovery required for iTerm2 target target-A'
  [[ -f $OVERRIDE_SUMMONINGS/${TIMESTAMP}-rq-willow.md ]] || fail_test 'promoted request missing'
  [[ ! -f $OVERRIDE_ANTECHAMBER/willow.md ]] || fail_test 'orphan request was restored'
  python3 - "$OVERRIDE_STORAGE" "$TEST_ROOT/iterm2.json" <<'PY'
import json, pathlib, sys
markers = list((pathlib.Path(sys.argv[1]) / 'recovery').glob('*.json'))
assert len(markers) == 1
record = json.loads(markers[0].read_text())
assert record['origin'] == 'origin-A' and record['target'] == 'target-A'
assert record['name'] == 'willow' and record['home'] == sys.argv[1]
assert 'target-A' in json.load(open(sys.argv[2]))['sessions']
PY
  create_request maple "$OVERRIDE_STORAGE" >/dev/null
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
    printf '{"sessions":{"origin-A":{"variable":{"origin":"origin-A","target":"target-A","name":"willow","timestamp":"260925-1435","harness":"codex","home":"/tmp/familiar"}},"target-A":{}},"events":[],"fail":"%s"}\n' "$failure" > "$TEST_ROOT/iterm2.json"
    if [[ $failure == close ]]; then
      output=$(run_iterm2 "$DISMISS" 2>&1) && fail_test 'close failure succeeded'
    else
      output=$(run_iterm2 "$MESSAGE" --message hello 2>&1) && fail_test "$failure failure succeeded"
    fi
    assert_contains "$output" 'session target-A'
    assert_not_contains "$output" 'pane target-A'
  done
}

test_iterm2_selection_and_preflight() {
  local output
  printf '{"sessions":{"origin-A":{}},"events":[]}\n' > "$TEST_ROOT/iterm2.json"
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" TMUX=1 ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=iterm2 "$STATUS" 2>&1) && fail_test 'nested iTerm2 succeeded'
  assert_contains "$output" 'cannot run inside tmux'
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" TMUX= ITERM_SESSION_ID=bad:id:extra FAMILIAR_BACKEND=iterm2 "$STATUS" 2>&1) && fail_test 'malformed origin succeeded'
  assert_contains "$output" 'valid ITERM_SESSION_ID'
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/realpath"
  chmod +x "$FAKE_BIN/realpath"
  output=$(run_iterm2 "$STATUS" 2>&1) && fail_test 'non-GNU realpath succeeded'
  assert_contains "$output" 'GNU coreutils realpath'
  rm -- "$FAKE_BIN/realpath"
  printf '#!/usr/bin/env bash\nprintf "not GNU\\n"\n' > "$FAKE_BIN/mv"
  chmod +x "$FAKE_BIN/mv"
  output=$(run_iterm2 "$STATUS" 2>&1) && fail_test 'non-GNU mv succeeded'
  assert_contains "$output" 'GNU coreutils mv'
  rm -- "$FAKE_BIN/mv"
  printf '#!/usr/bin/env bash\nexec python3 -I -S "$@"\n' > "$FAKE_BIN/python-no-iterm2"
  chmod +x "$FAKE_BIN/python-no-iterm2"
  output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" FAMILIAR_HOME="$OVERRIDE_STORAGE" TMUX= ITERM_SESSION_ID=w0t0p0:origin-A FAMILIAR_BACKEND=iterm2 FAMILIAR_ITERM2_PYTHON="$FAKE_BIN/python-no-iterm2" FAKE_ITERM2_STATE="$TEST_ROOT/iterm2.json" "$STATUS" 2>&1) && fail_test 'missing package succeeded'
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
}
