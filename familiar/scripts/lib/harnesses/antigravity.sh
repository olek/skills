#!/usr/bin/env bash
# Antigravity Familiar harness definition.

familiar_harness_executable() {
  printf 'agy\n'
}

familiar_harness_models() {
  agy models
}

familiar_harness_efforts() {
  printf '%s\n' low medium high
}

familiar_harness_intent_pair() {
  local -r intent=${1:-}

  # Placeholder until harness-specific intent model-effort pairs are known.
  case "$intent" in
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
  local command='exec agy'

  : "$working_directory" "$session_name" "$status_line_config"
  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  if [[ -n $effort ]]; then
    printf -v command '%s --effort %s' "$command" "$(shell_quote "$effort")"
  fi
  printf -v command '%s --prompt-interactive %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
