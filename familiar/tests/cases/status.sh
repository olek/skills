test_familiar_status() {
  local status_storage="$OVERRIDE_STORAGE"
  local FAMILIAR_HOME="$status_storage"
  local FAMILIAR_AUTO_DISMISS_SECONDS=''
  local FAKE_TMUX_AUTO_DISMISS_ENABLED=0
  local delivered_name
  local awaiting_name
  local invalid_name
  local dead_name
  local historical_name
  local historical_timestamp
  local delivered_response
  local invalid_response
  local historical_response
  local status_output
  local wait_output
  local invalid_output

  FAMILIAR_HOME="$status_storage"
  delivered_name='status-delivered'
  awaiting_name='status-awaiting'
  invalid_name='status-invalid'
  dead_name='status-dead'
  historical_name='historical-status'
  historical_timestamp='250101-1234'
  delivered_response=$(response_path_for "$delivered_name")
  invalid_response=$(response_path_for "$invalid_name")
  historical_response="$status_storage/summonings/$historical_timestamp-rs-$historical_name.md"
  touch -- "$delivered_response" "$historical_response"
  mkdir -p -- "$invalid_response"
  reset_fake_tmux
  write_pane '%4' '1' "$delivered_name" "$TIMESTAMP" codex "$status_storage" '%1' '0'
  write_pane '%5' '1' "$awaiting_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  write_pane '%7' '1' "$invalid_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  write_pane '%8' '1' "$dead_name" "$TIMESTAMP" codex "$status_storage" '%1' '1'
  write_pane '%9' '1' "$historical_name" "$historical_timestamp" claude "$status_storage" '%1' '0'
  write_pane '%15' '1' 'other-summoner' "$TIMESTAMP" codex "$status_storage" '%99' '0'
  FAMILIAR_HOME=''
  status_output=$(run_status)
  assert_contains "$status_output" 'Managed Familiar: status-delivered (codex, pane %4, response delivered)'
  assert_contains "$status_output" 'Managed Familiar: status-awaiting (claude, pane %5, awaiting response)'
  assert_contains "$status_output" 'Managed Familiar: status-invalid (claude, pane %7, response path invalid)'
  assert_contains "$status_output" 'Managed Familiar: status-dead (codex, pane %8, ended without response)'
  assert_contains "$status_output" "  request: $status_storage/summonings/$historical_timestamp-rq-$historical_name.md"
  assert_contains "$status_output" "  response: $historical_response"
  assert_not_contains "$status_output" 'other-summoner'
  FAMILIAR_HOME="$status_storage"

  reset_fake_tmux
  write_pane '%10' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  wait_output=$(run_status --wait --timeout 10)
  assert_not_contains "$wait_output" 'Timed out'
  assert_not_contains "$wait_output" 'Auto-dismiss'
  assert_contains "$wait_output" 'response delivered'

  reset_fake_tmux
  write_pane '%11' '1' "$invalid_name" "$TIMESTAMP" codex "$status_storage" '%1' '0'
  wait_output=$(run_status --wait --timeout 10)
  assert_not_contains "$wait_output" 'Timed out'
  assert_contains "$wait_output" 'response path invalid'

  reset_fake_tmux
  write_pane '%12' '1' "$awaiting_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  wait_output=$(run_status --wait --timeout 0)
  assert_contains "$wait_output" 'Timed out after 0 seconds'
  assert_contains "$wait_output" 'awaiting response'

  reset_fake_tmux
  write_pane '%13' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  FAKE_TMUX_AUTO_DISMISS_ENABLED=1
  wait_output=$(run_status --wait --auto-dismiss)
  FAKE_TMUX_AUTO_DISMISS_ENABLED=0
  assert_not_contains "$wait_output" 'Auto-dismissed Familiar pane'
  assert_contains "$wait_output" 'Auto-dismiss ended: the Familiar pane is closed.'
  assert_contains "$wait_output" 'No managed Familiar exists for this summoning agent instance.'

  reset_fake_tmux
  write_pane '%14' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
  FAMILIAR_AUTO_DISMISS_SECONDS='01'
  wait_output=$(run_status --wait --auto-dismiss)
  FAMILIAR_AUTO_DISMISS_SECONDS=''
  assert_contains "$wait_output" 'Auto-dismissed Familiar pane %14 after 1 seconds of user inspection.'
  assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'
  assert_contains "$wait_output" 'No managed Familiar exists for this summoning agent instance.'

  reset_fake_tmux
  invalid_output=''
  if invalid_output=$(run_status --auto-dismiss 2>&1); then
    fail_test 'expected --auto-dismiss without --wait to fail'
  fi
  assert_contains "$invalid_output" '--auto-dismiss requires --wait'

  reset_fake_tmux
  invalid_output=''
  if invalid_output=$(run_status --wait --auto-dismiss 1 2>&1); then
    fail_test 'expected a value after --auto-dismiss to fail'
  fi
  assert_contains "$invalid_output" '--auto-dismiss does not take a value'

  reset_fake_tmux
  FAMILIAR_AUTO_DISMISS_SECONDS='61'
  if run_status --wait --auto-dismiss >/dev/null 2>&1; then
    fail_test 'expected an auto-dismiss interval over 60 seconds to fail'
  fi
  FAMILIAR_AUTO_DISMISS_SECONDS=''

  reset_fake_tmux
  if run_status --wait --auto-dismiss --auto-dismiss >/dev/null 2>&1; then
    fail_test 'expected duplicate --auto-dismiss options to fail'
  fi

  reset_fake_tmux
  if run_status --auto-dismiss --timeout 0 >/dev/null 2>&1; then
    fail_test 'expected --auto-dismiss without explicit --wait to fail'
  fi

}
