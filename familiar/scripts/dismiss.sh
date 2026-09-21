#!/usr/bin/env bash
# Dismiss the one live Familiar managed by the current summoner.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/backend.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/familiar.sh"

usage() {
  printf 'Usage: %s\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

parse_arguments() {
  (($# == 0)) || {
    if [[ ${1:-} == --help && $# == 1 ]]; then
      usage
      exit 0
    fi
    usage
    fail "Unknown option: ${1:-}"
  }
}

main() {
  local familiar_name=''
  local familiar_id=''
  local summoner_id

  parse_arguments "$@"
  familiar_backend_require_context || exit 1
  summoner_id=$(familiar_backend_summoner_id)
  readonly summoner_id
  familiar_resolve_live_familiar familiar_name familiar_id "$summoner_id" || exit 1
  readonly familiar_name familiar_id
  if ! familiar_close_familiar "$familiar_id"; then
    fail "Could not dismiss Familiar $familiar_name in pane $familiar_id."
  fi
  printf 'Dismissed Familiar %s in pane %s.\n' "$familiar_name" "$familiar_id"
}

main "$@"
