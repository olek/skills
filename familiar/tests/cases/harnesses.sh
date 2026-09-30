# shellcheck shell=bash
test_familiar_harnesses() {
  local discovered_harnesses
  local unknown_harness_output
  local harness_copy
  local scratch_harnesses
  local loaded_scratch_executable
  local opencode_effort_command_output

  # Verify harness discovery and loading.
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

  opencode_effort_command_output=''
  if opencode_effort_command_output=$(
    bash -c 'source "$1"; familiar_harness_load opencode; familiar_harness_build_command /tmp session prompt model high' \
      -- "$HARNESS_LOADER" 2>&1
  ); then
    fail_test 'expected OpenCode command construction with an effort override to fail'
  fi
  assert_contains "$opencode_effort_command_output" 'does not support launch-time effort overrides'

  local claude_command
  claude_command=$(CLAUDECODE=1 DEBUG="a b'c" bash -c 'source "$1"; familiar_harness_load claude; familiar_harness_build_command /tmp session prompt "" ""' -- "$HARNESS_LOADER")
  assert_contains "$claude_command" "DEBUG='a b'\''c' CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 exec claude"
  claude_command=$(env -u CLAUDECODE DEBUG="a b'c" bash -c 'source "$1"; familiar_harness_load claude; familiar_harness_build_command /tmp session prompt "" ""' -- "$HARNESS_LOADER")
  assert_not_contains "$claude_command" 'DEBUG='
}
