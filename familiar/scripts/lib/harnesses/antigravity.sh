#!/usr/bin/env bash
# Antigravity Familiar harness definition.

familiar_harness_executable() {
  printf 'agy\n'
}

familiar_harness_build_command() {
  local -r familiar_prompt=$3
  local -r model=$4
  local -r effort=$5
  local command='exec agy'

  familiar_harness_append_option command --model "$model"
  familiar_harness_append_option command --effort "$effort"
  printf -v command '%s --prompt-interactive %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
