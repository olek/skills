#!/usr/bin/env bash
# Claude Code Familiar harness definition.

familiar_harness_executable() {
  printf 'claude\n'
}

familiar_harness_models() {
  printf '%s\n' fable opus sonnet haiku
}

familiar_harness_efforts() {
  printf '%s\n' low medium high xhigh max
}

familiar_harness_intent_pair() {
  local -r intent=${1:-}

  case "$intent" in
    planning|review)
      printf 'opus medium\n'
      ;;
    implementation)
      printf 'sonnet high\n'
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
  local command='CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 exec claude'

  : "$working_directory" "$status_line_config"
  printf -v command '%s --name %s' "$command" "$(shell_quote "$session_name")"
  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  if [[ -n $effort ]]; then
    printf -v command '%s --effort %s' "$command" "$(shell_quote "$effort")"
  fi
  printf -v command '%s %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
