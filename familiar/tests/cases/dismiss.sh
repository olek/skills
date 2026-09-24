test_familiar_dismiss() {
  local message_storage="$OVERRIDE_STORAGE"
  local FAMILIAR_HOME="$message_storage"
  local dismiss_name='dismiss-target'
  local dismiss_output
  local dismiss_state_before
  local arbitrary_target_output
  local no_familiar_output
  local closed_dismiss_output
  local multiple_dismiss_output
  local dismiss_help_output

  [[ -x $DISMISS ]] || fail_test 'expected the Familiar dismissal script to be executable'
  reset_fake_tmux
  write_pane '%28' '1' "$dismiss_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
  write_pane '%29' '1' 'other-summoner-dismiss' "$TIMESTAMP" codex "$message_storage" '%99' '0'
  dismiss_output=$(run_dismiss)
  assert_contains "$dismiss_output" "Dismissed Familiar $dismiss_name in pane %28."
  assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'
  assert_not_contains "$(<"$FAKE_TMUX_STATE")" '%28'
  assert_file_contains "$FAKE_TMUX_STATE" '%29'

  reset_fake_tmux
  write_pane '%30' '1' "$dismiss_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
  dismiss_state_before=$(<"$FAKE_TMUX_STATE")
  arbitrary_target_output=''
  if arbitrary_target_output=$(run_dismiss '%99' 2>&1); then
    fail_test 'expected dismissal with an arbitrary pane target to fail'
  fi
  assert_contains "$arbitrary_target_output" 'Unknown option: %99'
  assert_equals "$(<"$FAKE_TMUX_STATE")" "$dismiss_state_before"
  assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

  reset_fake_tmux
  no_familiar_output=''
  if no_familiar_output=$(run_dismiss 2>&1); then
    fail_test 'expected dismissal to fail when no Familiar exists'
  fi
  assert_contains "$no_familiar_output" 'No managed Familiar'
  assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

  reset_fake_tmux
  write_pane '%31' '1' 'closed-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '1'
  closed_dismiss_output=''
  if closed_dismiss_output=$(run_dismiss 2>&1); then
    fail_test 'expected dismissal to fail when only closed Familiars exist'
  fi
  assert_contains "$closed_dismiss_output" 'Only closed managed Familiars'
  assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

  reset_fake_tmux
  write_pane '%32' '1' 'first-live-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '0'
  write_pane '%33' '1' 'second-live-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '0'
  multiple_dismiss_output=''
  if multiple_dismiss_output=$(run_dismiss 2>&1); then
    fail_test 'expected dismissal to fail when multiple live Familiars exist'
  fi
  assert_contains "$multiple_dismiss_output" 'Multiple live managed Familiars'
  assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

  dismiss_help_output=$(run_dismiss --help 2>&1)
  assert_contains "$dismiss_help_output" 'Usage: dismiss.sh'
}
