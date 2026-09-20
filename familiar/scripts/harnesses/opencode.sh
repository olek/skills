#!/usr/bin/env bash
# OpenCode Familiar harness definition.

familiar_harness_executable() {
  printf 'opencode\n'
}

familiar_harness_models() {
  opencode models
}

familiar_harness_efforts() {
  printf 'OpenCode TUI does not support launch-time effort overrides.\n' >&2
  return 1
}

familiar_harness_intent_pair() {
  # Placeholder until harness-specific intent model-effort pairs are known.
  case "${1:-}" in
    planning|implementation|review)
      printf 'default default\n'
      ;;
    *)
      return 1
      ;;
  esac
}

familiar_harness_build_command() {
  local -r working_directory=$1
  local -r session_name=$2
  local -r familiar_prompt=$3
  local -r model=$4
  local -r effort=$5
  local -r status_line_config=$6
  local command='exec opencode'

  : "$working_directory" "$session_name" "$status_line_config"
  if [[ -n $effort ]]; then
    printf 'OpenCode TUI does not support launch-time effort overrides.\n' >&2
    return 1
  fi
  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  printf -v command '%s --prompt %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
