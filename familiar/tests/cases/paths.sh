# shellcheck shell=bash
test_familiar_paths() {
  local FAMILIAR_HOME=''
  local default_name
  local default_request
  local fresh_home
  local fresh_antechamber
  local fresh_request
  local override_name
  local override_request
  local invalid_output

  default_name='path-date-derived-familiar'
  default_request=$(create_request "$default_name" "$DEFAULT_HOME")
  assert_equals "$default_request" "$(run_config --request-path --name "$default_name")"

  # --request-path creates the antechamber directory so the summoning agent need not.
  fresh_home="$TEST_ROOT/fresh-home"
  fresh_antechamber="$fresh_home/antechamber"
  [[ ! -e $fresh_antechamber ]] || fail_test 'expected the fresh antechamber to be absent before --request-path'
  FAMILIAR_HOME="$fresh_home"
  fresh_request=$(run_config --request-path --name fresh-antechamber)
  FAMILIAR_HOME=''
  assert_equals "$fresh_request" "$fresh_antechamber/fresh-antechamber.md"
  [[ -d $fresh_antechamber ]] || fail_test 'expected --request-path to create the antechamber directory'
  [[ -d $fresh_home/config ]] || fail_test 'expected --request-path to create the configuration directory'
  [[ -d $fresh_home/summonings ]] || fail_test 'expected --request-path to create the summonings directory'

  FAMILIAR_HOME="$OVERRIDE_HOME"
  override_name='path-environment-override'
  override_request=$(create_request "$override_name" "$OVERRIDE_HOME")
  assert_equals "$override_request" "$(run_config --request-path --name "$override_name")"
  FAMILIAR_HOME=relative
  if invalid_output=$(run_config --request-path --name x 2>&1); then
    fail_test 'expected a relative Familiar home to fail path lookup'
  fi
  assert_contains "$invalid_output" 'FAMILIAR_HOME must be an absolute path.'
  if invalid_output=$(run_defaults --harness codex --intent review 2>&1); then
    fail_test 'expected a relative Familiar home to fail defaults lookup'
  fi
  assert_contains "$invalid_output" 'FAMILIAR_HOME must be an absolute path.'
  FAMILIAR_HOME=/
  if invalid_output=$(run_config --request-path --name x 2>&1); then
    fail_test 'expected root to fail Familiar home validation'
  fi
  assert_contains "$invalid_output" 'FAMILIAR_HOME must be an absolute path.'
  FAMILIAR_HOME=''
  if invalid_output=$(env -u HOME FAMILIAR_HOME='' "$PATHS_SCRIPT" --request-path --name x 2>&1); then
    fail_test 'expected an unset HOME to fail path lookup'
  fi
  assert_contains "$invalid_output" 'HOME must be set when FAMILIAR_HOME is not set.'
  local removed_output
  removed_output=$(run_config --directory 2>&1) && fail_test "removed option succeeded"
  assert_contains "$removed_output" "Unknown option"
}
