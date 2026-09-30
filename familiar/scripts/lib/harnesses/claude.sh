#!/usr/bin/env bash
# Claude Code Familiar harness definition.

familiar_harness_executable() {
  printf 'claude\n'
}

familiar_harness_build_command() {
  local -r session_name=$2
  local -r familiar_prompt=$3
  local -r model=$4
  local -r effort=$5
  local command='CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 exec claude'

  # A Claude summoner's DEBUG reaches only this process, not the new pane.
  if [[ ${CLAUDECODE:-} == 1 && -n ${DEBUG:-} ]]; then
    command="DEBUG=$(shell_quote "$DEBUG") $command"
  fi
  printf -v command '%s --name %s' "$command" "$(shell_quote "$session_name")"
  familiar_harness_append_option command --model "$model"
  familiar_harness_append_option command --effort "$effort"
  printf -v command '%s %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}
