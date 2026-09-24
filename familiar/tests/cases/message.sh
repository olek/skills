test_familiar_message() {
  local message_storage="$OVERRIDE_STORAGE"
  local FAMILIAR_HOME="$message_storage"
  local message_name
  local message_request
  local message_response
  local message_text
  local message_state_before
  local message_output
  local expected_send_keys_args
  local closed_output
  local no_familiar_output
  local multiple_output
  local FAKE_TMUX_FAIL_SEND_KEYS=''
  local first_send_failure_output
  local enter_failure_output
  local message_help_output
  local invalid_message_arguments
  local -a invalid_message_argv
  local tmux_validation_output

  [[ -x $MESSAGE ]] || fail_test 'expected the Familiar message script to be executable'
  FAMILIAR_HOME="$message_storage"
  message_name='message-target'
  message_request=$(create_request "$message_name" "$message_storage")
  message_response=$(response_path_for "$message_name")
  message_text='-follow-up text'
  reset_fake_tmux
  write_pane '%20' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
  write_pane '%21' '1' 'other-summoner-message' "$TIMESTAMP" codex "$message_storage" '%99' '0'
  write_pane '%22' '1' 'closed-message' "$TIMESTAMP" codex "$message_storage" '%1' '1'
  message_state_before=$(<"$FAKE_TMUX_STATE")
  message_output=$(run_message --message "$message_text")
  assert_contains "$message_output" "Sent message to Familiar $message_name in pane %20."
  expected_send_keys_args=$'send-keys\n-t\n%20\n-l\n--\n-follow-up text\nEND_CALL\nsend-keys\n-t\n%20\nC-m\nEND_CALL'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" "$expected_send_keys_args"
  assert_equals "$(<"$FAKE_SLEEP_ARGS")" '0.1'
  assert_equals "$(<"$FAKE_TMUX_CALLS")" $'list-panes\nsend-keys\nsleep\nsend-keys'
  assert_equals "$(<"$FAKE_TMUX_STATE")" "$message_state_before"
  [[ -f $message_request ]] || fail_test 'message delivery changed the request file'
  [[ ! -e $message_response ]] || fail_test 'message delivery created the response file'

  reset_fake_tmux
  write_pane '%23' '1' 'closed-only' "$TIMESTAMP" codex "$message_storage" '%1' '1'
  closed_output=''
  if closed_output=$(run_message --message 'hello' 2>&1); then
    fail_test 'expected a message to fail when only closed Familiars exist'
  fi
  assert_contains "$closed_output" 'Only closed managed Familiars'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

  reset_fake_tmux
  no_familiar_output=''
  if no_familiar_output=$(run_message --message 'hello' 2>&1); then
    fail_test 'expected a message to fail when no Familiar exists'
  fi
  assert_contains "$no_familiar_output" 'No managed Familiar'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

  reset_fake_tmux
  write_pane '%24' '1' 'first-live' "$TIMESTAMP" codex "$message_storage" '%1' '0'
  write_pane '%25' '1' 'second-live' "$TIMESTAMP" codex "$message_storage" '%1' '0'
  multiple_output=''
  if multiple_output=$(run_message --message 'hello' 2>&1); then
    fail_test 'expected a message to fail when multiple live Familiars exist'
  fi
  assert_contains "$multiple_output" 'Multiple live managed Familiars'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

  reset_fake_tmux
  write_pane '%26' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
  FAKE_TMUX_FAIL_SEND_KEYS='1'
  first_send_failure_output=''
  if first_send_failure_output=$(run_message --message 'hello' 2>&1); then
    fail_test 'expected the message to fail when text delivery fails'
  fi
  FAKE_TMUX_FAIL_SEND_KEYS=''
  assert_contains "$first_send_failure_output" 'Could not deliver the message'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_COUNT")" '1'

  reset_fake_tmux
  write_pane '%27' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
  FAKE_TMUX_FAIL_SEND_KEYS='2'
  enter_failure_output=''
  if enter_failure_output=$(run_message --message 'hello' 2>&1); then
    fail_test 'expected the message to fail when Enter delivery fails'
  fi
  FAKE_TMUX_FAIL_SEND_KEYS=''
  assert_contains "$enter_failure_output" 'the message may remain unsubmitted'
  assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_COUNT")" '2'

  message_help_output=$(run_message --help 2>&1)
  assert_contains "$message_help_output" 'Usage: message.sh --message <text>'
  for invalid_message_arguments in \
    '' \
    '--message' \
    '--message one --message two' \
    '--message one extra' \
    '--unknown'; do
    read -r -a invalid_message_argv <<< "$invalid_message_arguments"
    if run_message "${invalid_message_argv[@]}" >/dev/null 2>&1; then
      fail_test "expected invalid message arguments to fail: $invalid_message_arguments"
    fi
  done

  tmux_validation_output=''
  if tmux_validation_output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" \
    FAMILIAR_HOME="$message_storage" TMUX='' TMUX_PANE='%1' \
    "$MESSAGE" --message hello 2>&1); then
    fail_test 'expected message delivery outside tmux to fail'
  fi
  assert_contains "$tmux_validation_output" 'must run inside tmux'

  tmux_validation_output=''
  if tmux_validation_output=$(env PATH="$FAKE_BIN:$PATH" HOME="$TEST_HOME" \
    FAMILIAR_HOME="$message_storage" TMUX=1 TMUX_PANE='' \
    "$MESSAGE" --message hello 2>&1); then
    fail_test 'expected message delivery without a tmux pane to fail'
  fi
  assert_contains "$tmux_validation_output" 'must run from a tmux pane'
}
