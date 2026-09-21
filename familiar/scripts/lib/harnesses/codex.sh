#!/usr/bin/env bash
# Codex Familiar harness definition.
# Refresh the embedded catalog by hand from ~/.codex/models_cache.json.

familiar_harness_executable() {
  printf 'codex\n'
}

familiar_harness_models() {
  printf '%s\n' gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna gpt-5.5
}

familiar_harness_efforts() {
  printf '%s\n' low medium high xhigh max ultra
}

familiar_harness_intent_pair() {
  local -r intent=${1:-}

  case "$intent" in
    planning|review)
      printf 'gpt-5.6-sol medium\n'
      ;;
    implementation)
      printf 'gpt-5.6-terra medium\n'
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
  local command='exec codex --no-alt-screen'

  : "$session_name"
  printf -v command '%s --config %s' "$command" "$(shell_quote "$status_line_config")"

  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  if [[ -n $effort ]]; then
    printf -v command '%s --config %s' "$command" "$(shell_quote "model_reasoning_effort=$effort")"
  fi
  printf -v command '%s --cd %s %s' "$command" \
    "$(shell_quote "$working_directory")" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
