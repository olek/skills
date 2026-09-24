test_familiar_paths() {
  local FAMILIAR_HOME=''
  local default_name
  local default_request
  local default_response
  local fresh_home
  local fresh_antechamber
  local fresh_request
  local override_name
  local override_request
  local override_response

  default_name='path-date-derived-familiar'
  default_request=$(create_request "$default_name" "$DEFAULT_STORAGE")
  default_response=$(response_path_for "$default_name")
  assert_equals "$(run_config --directory)" "$DEFAULT_STORAGE"
  assert_equals "$(run_config --antechamber-directory)" "$DEFAULT_ANTECHAMBER"
  assert_equals "$(run_config --session-name --name "$default_name")" "$TIMESTAMP-fm-$default_name"
  assert_equals "$default_request" "$(run_config --request-path --name "$default_name")"
  assert_equals "$default_response" "$DEFAULT_STORAGE/$TIMESTAMP-rs-$default_name.md"
  assert_equals "$(run_config --session-name --name '260918-task')" "$TIMESTAMP-fm-260918-task"

  # --request-path creates the antechamber directory so the summoning agent need not.
  fresh_home="$TEST_ROOT/fresh-home"
  fresh_antechamber="$fresh_home/antechamber"
  [[ ! -e $fresh_antechamber ]] || fail_test 'expected the fresh antechamber to be absent before --request-path'
  FAMILIAR_HOME="$fresh_home"
  fresh_request=$(run_config --request-path --name fresh-antechamber)
  FAMILIAR_HOME=''
  assert_equals "$fresh_request" "$fresh_antechamber/fresh-antechamber.md"
  [[ -d $fresh_antechamber ]] || fail_test 'expected --request-path to create the antechamber directory'

  FAMILIAR_HOME="$OVERRIDE_STORAGE"
  override_name='path-environment-override'
  override_request=$(create_request "$override_name" "$OVERRIDE_STORAGE")
  override_response=$(response_path_for "$override_name")
  assert_equals "$(run_config --directory)" "$OVERRIDE_STORAGE"
  assert_equals "$(run_config --antechamber-directory)" "$OVERRIDE_ANTECHAMBER"
  assert_equals "$override_request" "$(run_config --request-path --name "$override_name")"
  assert_equals "$override_response" "$OVERRIDE_STORAGE/$TIMESTAMP-rs-$override_name.md"
}
