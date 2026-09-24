test_familiar_summon() {
  local work_directory="$TEST_ROOT/familiar dir's space"
  local FAMILIAR_HOME=''
  local default_name='summon-default'
  local default_request
  local default_timestamped_request="$DEFAULT_STORAGE/$TIMESTAMP-rq-$default_name.md"
  local default_response
  local override_name='summon-environment-override'
  local override_request
  local override_timestamped_request="$OVERRIDE_STORAGE/$TIMESTAMP-rq-$override_name.md"
  local override_response
  local override_launch_output
  local override_command
  local default_launch_output
  local default_command
  local codex_name codex_command claude_name claude_command
  local opencode_name opencode_command antigravity_name antigravity_command
  local default_option explicit_default_output invalid_name other_summoner_name
  local guard_name guard_request collision_name collision_request
  local split_failure_name split_failure_request metadata_failure_name metadata_failure_request

  [[ -x $LAUNCHER ]] || fail_test 'expected the Familiar summon script to be executable'
  mkdir -p -- "$work_directory"
  default_request=$(create_request "$default_name" "$DEFAULT_STORAGE")
  default_response=$(response_path_for "$default_name")
  FAMILIAR_HOME="$OVERRIDE_STORAGE"
  override_request=$(create_request "$override_name" "$OVERRIDE_STORAGE")
  override_response=$(response_path_for "$override_name")

  reset_fake_tmux
  override_launch_output=$(run_launcher --name "$override_name" --cwd "$work_directory" --harness claude)
  override_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$override_command" "--name $(shell_quote "$TIMESTAMP-fm-$override_name")"
  assert_contains "$override_command" "The resolved response path is $override_response"
  assert_contains "$override_launch_output" "request: $override_timestamped_request"
  assert_contains "$override_launch_output" "response: $override_response"
  [[ ! -e $override_request ]] || fail_test 'expected the staged override request to be promoted'
  [[ -f $override_timestamped_request ]] || fail_test 'expected the timestamped override request to exist'

  FAMILIAR_HOME=''
  reset_fake_tmux
  default_launch_output=$(run_launcher --name "$default_name" --cwd "$work_directory" --harness codex)
  default_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$default_command" 'exec codex --no-alt-screen'
  assert_not_contains "$default_command" '--approve-for-me'
  assert_contains "$default_command" "--config $(shell_quote 'tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]')"
  assert_contains "$default_command" "--cd $(shell_quote "$work_directory")"
  assert_contains "$default_command" "$default_timestamped_request"
  assert_contains "$default_command" "$default_response"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar\t1'
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t'"$default_name"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_timestamp\t'"$TIMESTAMP"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_home\t'"$DEFAULT_STORAGE"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_summoner_pane\t%1'
  assert_contains "$default_launch_output" 'pane-new'
  assert_contains "$default_launch_output" "request: $default_timestamped_request"
  assert_contains "$default_launch_output" "response: $default_response"
  [[ ! -e $default_request ]] || fail_test 'expected the staged request to be promoted'
  [[ -f $default_timestamped_request ]] || fail_test 'expected the timestamped request to exist'

  codex_name='codex-model-selection'
  create_request "$codex_name" "$DEFAULT_STORAGE" >/dev/null
  reset_fake_tmux
  run_launcher --name "$codex_name" --cwd "$work_directory" --harness codex --model gpt-5.6-luna --effort high >/dev/null
  codex_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$codex_command" "--model $(shell_quote gpt-5.6-luna)"
  assert_contains "$codex_command" "--config $(shell_quote 'model_reasoning_effort=high')"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'

  claude_name='claude-model-selection'
  create_request "$claude_name" "$DEFAULT_STORAGE" >/dev/null
  reset_fake_tmux
  run_launcher --name "$claude_name" --cwd "$work_directory" --harness claude --model sonnet --effort ultra >/dev/null
  claude_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$claude_command" 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1'
  assert_contains "$claude_command" 'exec claude'
  assert_not_contains "$claude_command" '--permission-mode'
  assert_contains "$claude_command" "--name $(shell_quote "$TIMESTAMP-fm-$claude_name")"
  assert_contains "$claude_command" "--model $(shell_quote sonnet)"
  assert_contains "$claude_command" "--effort $(shell_quote ultra)"
  assert_not_contains "$claude_command" 'codex'
  assert_not_contains "$claude_command" '--approve-for-me'
  assert_not_contains "$claude_command" '--no-alt-screen'
  assert_not_contains "$claude_command" '--cd'
  assert_not_contains "$claude_command" '--config'
  assert_not_contains "$claude_command" 'model_reasoning_effort'
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t'"$claude_name"
  assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_timestamp\t'"$TIMESTAMP"

  opencode_name='opencode-model-selection'
  create_request "$opencode_name" "$DEFAULT_STORAGE" >/dev/null
  reset_fake_tmux
  run_launcher --name "$opencode_name" --cwd "$work_directory" --harness opencode --model provider/model >/dev/null
  opencode_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$opencode_command" 'exec opencode'
  assert_contains "$opencode_command" "--model $(shell_quote provider/model)"
  assert_contains "$opencode_command" '--prompt '
  assert_contains "$opencode_command" "$TIMESTAMP-rs-$opencode_name.md"
  assert_not_contains "$opencode_command" '--auto'
  assert_not_contains "$opencode_command" '--effort'

  antigravity_name='antigravity-model-selection'
  create_request "$antigravity_name" "$DEFAULT_STORAGE" >/dev/null
  reset_fake_tmux
  run_launcher --name "$antigravity_name" --cwd "$work_directory" --harness antigravity --model gemini-pro --effort high >/dev/null
  antigravity_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
  assert_contains "$antigravity_command" 'exec agy'
  assert_contains "$antigravity_command" "--model $(shell_quote gemini-pro)"
  assert_contains "$antigravity_command" "--effort $(shell_quote high)"
  assert_contains "$antigravity_command" '--prompt-interactive '
  assert_contains "$antigravity_command" "$TIMESTAMP-rs-$antigravity_name.md"
  assert_not_contains "$antigravity_command" '--dangerously-skip-permissions'

  # Invalid input and launch failures must not consume the staged request.
  for default_option in model effort; do
    reset_fake_tmux
    explicit_default_output=''
    if explicit_default_output=$(run_launcher \
      --name "explicit-default-$default_option" \
      --cwd "$work_directory" \
      --harness codex \
      "--$default_option" default 2>&1); then
      fail_test "expected explicit --$default_option default to fail"
    fi
    assert_contains "$explicit_default_output" "Omit --$default_option to use the harness-configured default."
    assert_no_split
  done

  for invalid_name in \
    'fm-task' \
    'rq-task' \
    'rs-task' \
    'Bad-name' \
    'name_with_underscore' \
    'name with spaces'; do
    reset_fake_tmux
    if run_launcher --name "$invalid_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
      fail_test "expected launcher failure for invalid name: $invalid_name"
    fi
    assert_no_split
  done

  reset_fake_tmux
  if run_launcher --name 'invalid-harness' --cwd "$work_directory" --harness unknown >/dev/null 2>&1; then
    fail_test 'expected an unknown harness to fail'
  fi
  assert_no_split

  reset_fake_tmux
  if run_launcher --name 'duplicate-harness' --cwd "$work_directory" --harness claude --harness codex >/dev/null 2>&1; then
    fail_test 'expected duplicate harness options to fail'
  fi
  assert_no_split

  reset_fake_tmux
  if run_launcher --name 'missing-harness' --cwd "$work_directory" --harness >/dev/null 2>&1; then
    fail_test 'expected a missing harness value to fail'
  fi
  assert_no_split

  reset_fake_tmux
  if run_launcher --name 'absent-harness' --cwd "$work_directory" >/dev/null 2>&1; then
    fail_test 'expected an omitted --harness to fail'
  fi
  assert_no_split

  other_summoner_name='other-summoner-allowed'
  create_request "$other_summoner_name" "$DEFAULT_STORAGE" >/dev/null
  reset_fake_tmux
  write_pane '%2' '1' 'other-summoner-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%99' '0'
  run_launcher --name "$other_summoner_name" --cwd "$work_directory" --harness codex >/dev/null
  assert_file_contains "$FAKE_TMUX_CALLS" 'split-window'

  guard_name='guarded-launch'
  guard_request=$(create_request "$guard_name" "$DEFAULT_STORAGE")
  reset_fake_tmux
  write_pane '%2' '1' 'existing-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%1' '0'
  if run_launcher --name "$guard_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
    fail_test 'expected an existing managed Familiar to block the launch'
  fi
  assert_no_split
  [[ -f $guard_request ]] || fail_test 'expected a blocked launch to preserve the staged request'

  collision_name='durable-collision'
  collision_request=$(create_request "$collision_name" "$DEFAULT_STORAGE")
  touch -- "$DEFAULT_STORAGE/$TIMESTAMP-rq-$collision_name.md"
  reset_fake_tmux
  if run_launcher --name "$collision_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
    fail_test 'expected an existing durable request to block the launch'
  fi
  assert_no_split
  [[ -f $collision_request ]] || fail_test 'expected a collision to preserve the staged request'

  split_failure_name='split-failure'
  split_failure_request=$(create_request "$split_failure_name" "$DEFAULT_STORAGE")
  reset_fake_tmux
  FAKE_TMUX_FAIL_COMMAND='split-window'
  if run_launcher --name "$split_failure_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
    fail_test 'expected a split-window failure'
  fi
  FAKE_TMUX_FAIL_COMMAND=''
  [[ -f $split_failure_request ]] || fail_test 'expected split failure to restore the staged request'
  [[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-rq-$split_failure_name.md ]] || fail_test 'expected no durable request after split failure'

  metadata_failure_name='metadata-failure'
  metadata_failure_request=$(create_request "$metadata_failure_name" "$DEFAULT_STORAGE")
  reset_fake_tmux
  FAKE_TMUX_FAIL_SET_OPTION='@familiar_home'
  if run_launcher --name "$metadata_failure_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
    fail_test 'expected a metadata failure'
  fi
  FAKE_TMUX_FAIL_SET_OPTION=''
  [[ -f $metadata_failure_request ]] || fail_test 'expected metadata failure to restore the staged request'
  [[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-rq-$metadata_failure_name.md ]] || fail_test 'expected no durable request after metadata failure'
  assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'
}
