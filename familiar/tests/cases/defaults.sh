# shellcheck shell=bash
test_familiar_defaults() {
  local default_intent_harness intent config_file config_output
  local discovered_harnesses
  discovered_harnesses=$(bash -c 'source "$1"; familiar_harness_all' -- "$HARNESS_LOADER")
  while IFS= read -r default_intent_harness; do
    for intent in planning implementation review; do
      assert_default_pair_contract "$default_intent_harness" "$intent"
    done
  done <<< "$discovered_harnesses"

  FAMILIAR_HOME="$OVERRIDE_HOME"
  config_file="$OVERRIDE_HOME/config/intent.conf"
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

  printf '%s\n' \
    'codex.planning = first-model medium' \
    'claude.review = first-model high' \
    'claude.review = second-model low' > "$config_file"
  config_output=$(run_defaults --harness codex --intent planning 2>&1) && fail_test 'unrelated duplicate intent succeeded'
  assert_contains "$config_output" 'Duplicate Familiar intent entry for claude.review'

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
