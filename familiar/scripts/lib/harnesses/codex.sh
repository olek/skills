#!/usr/bin/env bash
# Codex Familiar harness definition.

familiar_harness_executable() {
  printf 'codex\n'
}

familiar_harness_build_command() {
  local -r working_directory=$1
  local -r familiar_prompt=$3
  local -r model=$4
  local -r effort=$5
  local -r status_line_config='tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]'
  local command='exec codex --no-alt-screen'

  familiar_harness_append_option command --config "$status_line_config"
  familiar_harness_append_option command --model "$model"
  if [[ -n $effort ]]; then
    familiar_harness_append_option command --config "model_reasoning_effort=$effort"
  fi
  printf -v command '%s --cd %s %s' "$command" \
    "$(shell_quote "$working_directory")" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
