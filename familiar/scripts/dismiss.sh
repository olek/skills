#!/usr/bin/env bash
# Dismiss the one live Familiar managed by the current summoning pane.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/pane.sh"

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
  local pane_id=''

  parse_arguments "$@"
  [[ -n ${TMUX:-} ]] || fail 'This dismissal command must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This dismissal command must run from a tmux pane.'
  familiar_resolve_live_familiar familiar_name pane_id "$TMUX_PANE" || exit 1
  readonly familiar_name pane_id
  if ! familiar_close_pane "$pane_id"; then
    fail "Could not dismiss Familiar $familiar_name in pane $pane_id."
  fi
  printf 'Dismissed Familiar %s in pane %s.\n' "$familiar_name" "$pane_id"
}

main "$@"
