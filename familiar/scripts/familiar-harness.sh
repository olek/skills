#!/usr/bin/env bash
# Shared Familiar harness discovery, loading, and command quoting.
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
  local -r harness_file=$1
  local -r harness_name=${harness_file##*/}

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
  local -r requested_harness=${1:-}
  local harness_file

  [[ -n $requested_harness ]] || return 1
  for harness_file in "$FAMILIAR_HARNESS_DIRECTORY"/*.sh; do
    [[ -f $harness_file ]] || continue
    [[ ${harness_file##*/} == "$requested_harness.sh" ]] && return 0
  done
  return 1
}

familiar_harness_load() {
  local -r harness=${1:-}
  local harness_file

  familiar_harness_is_known "$harness" || {
    printf 'Unknown Familiar harness: %s\n' "$harness" >&2
    return 1
  }
  harness_file="$FAMILIAR_HARNESS_DIRECTORY/$harness.sh"
  # shellcheck disable=SC1090
  source "$harness_file"
}
