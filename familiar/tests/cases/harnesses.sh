test_familiar_harnesses() {
  local discovered_harnesses
    local unknown_harness_output
    local harness_copy
    local scratch_harnesses
    local loaded_scratch_executable
    local default_intent_harness
    local intent
  local opencode_effort_command_output
  local config_file
  local config_output

  # Verify harness discovery and default intent choices.
  discovered_harnesses=$(bash -c 'source "$1"; familiar_harness_all' -- "$HARNESS_LOADER")
  [[ -n $discovered_harnesses ]] || fail_test 'expected at least one discovered harness'

  unknown_harness_output=''
  if unknown_harness_output=$(bash -c 'source "$1"; familiar_harness_load "$2"' -- "$HARNESS_LOADER" unknown 2>&1); then
    fail_test 'expected loading an unknown harness to fail'
  fi
  assert_contains "$unknown_harness_output" 'Unknown Familiar harness: unknown'

  harness_copy="$TEST_ROOT/harness-copy"
  mkdir -p -- "$harness_copy/lib/harnesses"
  cp -- "$HARNESS_LOADER" "$harness_copy/lib/harness.sh"
  cat > "$harness_copy/lib/harnesses/scratch.sh" <<'SCRATCH_HARNESS'
#!/usr/bin/env bash

familiar_harness_executable() {
  printf 'scratch\n'
}
SCRATCH_HARNESS
  scratch_harnesses=$(bash -c 'source "$1"; familiar_harness_all' -- "$harness_copy/lib/harness.sh")
  assert_contains "$scratch_harnesses" 'scratch'
  loaded_scratch_executable=$(
    bash -c 'source "$1"; familiar_harness_load scratch; familiar_harness_executable' -- "$harness_copy/lib/harness.sh"
  )
  assert_equals "$loaded_scratch_executable" 'scratch'

  while IFS= read -r default_intent_harness; do
    for intent in planning implementation review; do
      assert_default_pair_contract "$default_intent_harness" "$intent"
    done
  done <<< "$discovered_harnesses"

  opencode_effort_command_output=''
  if opencode_effort_command_output=$(
    bash -c 'source "$1"; familiar_harness_load opencode; familiar_harness_build_command /tmp session prompt model high config' \
      -- "$HARNESS_LOADER" 2>&1
  ); then
    fail_test 'expected OpenCode command construction with an effort override to fail'
  fi
  assert_contains "$opencode_effort_command_output" 'does not support launch-time effort overrides'
  FAMILIAR_HOME="$OVERRIDE_STORAGE"
  config_file="$OVERRIDE_STORAGE/config/intent.conf"
  mkdir -p -- "${config_file%/*}"
  printf '%s\n' \
    '# User-owned intent choices.' \
    'codex.planning = local-planning-model high' \
    'claude.review = default default' \
    'antigravity.implementation = local-antigravity-model medium' \
    'opencode.planning = provider/local-model default' > "$config_file"
  assert_equals "$(run_defaults --harness codex --intent planning)" \
    $'model=local-planning-model\neffort=high\nconfiguration=present\nmissing_intents=implementation,review\nconfiguration_path='"$config_file"
  assert_equals "$(run_defaults --harness claude --intent review)" \
    $'model=default\neffort=default\nconfiguration=present\nmissing_intents=planning,implementation\nconfiguration_path='"$config_file"
  assert_equals "$(run_defaults --harness antigravity --intent implementation)" \
    $'model=local-antigravity-model\neffort=medium\nconfiguration=present\nmissing_intents=planning,review\nconfiguration_path='"$config_file"
  assert_equals "$(run_defaults --harness opencode --intent planning)" \
    $'model=provider/local-model\neffort=default\nconfiguration=present\nmissing_intents=implementation,review\nconfiguration_path='"$config_file"
  assert_equals "$(run_defaults --harness codex --intent review)" \
    $'model=default\neffort=default\nconfiguration=present\nmissing_intents=implementation,review\nconfiguration_path='"$config_file"

  printf '%s\n' \
    'codex.planning = local-planning-model high' \
    'claude.review = local-review-model high' > "$config_file"
  assert_equals "$(run_defaults --harness antigravity --intent implementation)" \
    $'model=default\neffort=default\nconfiguration=present\nmissing_intents=planning,implementation,review\nconfiguration_path='"$config_file"

  printf '%s\n' \
    'antigravity.planning = planning-model medium' \
    'antigravity.implementation = implementation-model low' \
    'antigravity.review = review-model high' > "$config_file"
  assert_equals "$(run_defaults --harness antigravity --intent review)" \
    $'model=review-model\neffort=high\nconfiguration=present\nmissing_intents=\nconfiguration_path='"$config_file"

  printf '%s\n' \
    'codex.planning = first-model medium' \
    'codex.planning = second-model high' > "$config_file"
  config_output=''
  if config_output=$(run_defaults --harness codex --intent planning 2>&1); then
    fail_test 'expected a duplicate intent entry to fail'
  fi
  assert_contains "$config_output" 'Duplicate Familiar intent entry for codex.planning'

  printf '%s\n' 'codex.planning = first-model' > "$config_file"
  config_output=''
  if config_output=$(run_defaults --harness codex --intent planning 2>&1); then
    fail_test 'expected a malformed intent entry to fail'
  fi
  assert_contains "$config_output" 'expected <harness>.<intent> = <model> <effort>'
  printf '%s\n' 'unknown.implementation = local-model medium' > "$config_file"
  config_output=''
  if config_output=$(run_defaults --harness antigravity --intent implementation 2>&1); then
    fail_test 'expected an unknown harness key to fail'
  fi
  assert_contains "$config_output" 'Unknown Familiar harness in intent configuration'
  rm -- "$config_file"
  assert_equals "$(run_defaults --harness antigravity --intent implementation)" \
    $'model=default\neffort=default\nconfiguration=missing\nmissing_intents=planning,implementation,review\nconfiguration_path='"$config_file"
  config_output=''
  if config_output=$(run_defaults --harness codex --intent unknown 2>&1); then
    fail_test 'expected unknown intent to fail'
  fi
  assert_contains "$config_output" 'Unknown Familiar intent: unknown'
  FAMILIAR_HOME=''
}

# A managed Familiar pane's metadata, one row per pane:
