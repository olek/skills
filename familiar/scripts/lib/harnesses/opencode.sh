#!/usr/bin/env bash
# OpenCode Familiar harness definition.

familiar_harness_executable() {
  printf 'opencode\n'
}

familiar_harness_build_command() {
  local -r familiar_prompt=$3
  local -r model=$4
  local -r effort=$5
  local command='exec opencode'

  if [[ -n $effort ]]; then
    printf 'OpenCode TUI does not support launch-time effort overrides.\n' >&2
    return 1
  fi
  familiar_harness_append_option command --model "$model"
  printf -v command '%s --prompt %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
