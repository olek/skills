test_familiar_harnesses() {
  local discovered_harnesses
    local unknown_harness_output
    local harness_copy
    local scratch_harnesses
    local loaded_scratch_executable
    local default_intent_harness
    local intent
    local opencode_models
    local opencode_efforts_output
    local opencode_effort_command_output
  local antigravity_models

  # Verify harness discovery and each harness's advertised launch choices.
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

  opencode_models=$(run_models --harness opencode)
  assert_contains "$opencode_models" 'provider/opencode-test-model'
  opencode_efforts_output=''
  if opencode_efforts_output=$(run_efforts --harness opencode 2>&1); then
    fail_test 'expected OpenCode effort discovery to report unsupported launch-time overrides'
  fi
  assert_contains "$opencode_efforts_output" 'does not support launch-time effort overrides'
  opencode_effort_command_output=''
  if opencode_effort_command_output=$(
    bash -c 'source "$1"; familiar_harness_load opencode; familiar_harness_build_command /tmp session prompt model high config' \
      -- "$HARNESS_LOADER" 2>&1
  ); then
    fail_test 'expected OpenCode command construction with an effort override to fail'
  fi
  assert_contains "$opencode_effort_command_output" 'does not support launch-time effort overrides'
  antigravity_models=$(run_models --harness antigravity)
  assert_contains "$antigravity_models" 'antigravity-test-model'
}

# A managed Familiar pane's metadata, one row per pane:
