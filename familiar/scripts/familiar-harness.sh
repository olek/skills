#!/usr/bin/env bash
# Shared Familiar harness discovery, dispatch, and command quoting.
set -euo pipefail

FAMILIAR_HARNESS_SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly FAMILIAR_HARNESS_SCRIPT_DIRECTORY
readonly FAMILIAR_HARNESS_DIRECTORY="$FAMILIAR_HARNESS_SCRIPT_DIRECTORY/harnesses"

shell_quote() {
  local escaped_value=$1
  escaped_value=${escaped_value//\'/\'"\'"\'}
  printf "'%s'" "$escaped_value"
}

familiar_harness_name_for_file() {
  local harness_file=$1
  local harness_name=${harness_file##*/}

  printf '%s\n' "${harness_name%.sh}"
}

familiar_harness_all() {
  local harness_file

  for harness_file in "$FAMILIAR_HARNESS_DIRECTORY"/*.sh; do
    [[ -f $harness_file ]] || continue
    familiar_harness_name_for_file "$harness_file"
  done | sort
}

familiar_harness_is_known() {
  local requested_harness=${1:-}
  local harness_file

  [[ -n $requested_harness ]] || return 1
  for harness_file in "$FAMILIAR_HARNESS_DIRECTORY"/*.sh; do
    [[ -f $harness_file ]] || continue
    [[ ${harness_file##*/} == "$requested_harness.sh" ]] && return 0
  done
  return 1
}

familiar_harness_source_definitions() {
  local harness_file

  for harness_file in "$FAMILIAR_HARNESS_DIRECTORY"/*.sh; do
    [[ -f $harness_file ]] || continue
    # shellcheck disable=SC1090
    source "$harness_file"
  done
}

familiar_harness_dispatch() {
  local -r capability=$1
  local -r harness=$2
  local function_name
  shift 2

  if ! familiar_harness_is_known "$harness"; then
    printf 'Unknown Familiar harness: %s\n' "$harness" >&2
    return 1
  fi

  function_name="familiar_harness_${harness}_${capability}"
  if ! declare -F "$function_name" >/dev/null 2>&1; then
    printf 'Familiar harness %s does not implement capability: %s\n' "$harness" "$capability" >&2
    return 1
  fi
  "$function_name" "$@"
}

familiar_harness_executable() {
  familiar_harness_dispatch executable "$@"
}

familiar_harness_models() {
  familiar_harness_dispatch models "$@"
}

familiar_harness_efforts() {
  familiar_harness_dispatch efforts "$@"
}

familiar_harness_validate_effort() {
  familiar_harness_dispatch validate_effort "$@"
}

familiar_harness_intent_model() {
  familiar_harness_dispatch intent_model "$@"
}

familiar_harness_intent_effort() {
  familiar_harness_dispatch intent_effort "$@"
}

familiar_harness_supports_session_name() {
  familiar_harness_dispatch supports_session_name "$@"
}

familiar_harness_build_command() {
  familiar_harness_dispatch build_command "$@"
}

familiar_harness_source_definitions
