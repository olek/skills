#!/usr/bin/env bash
# Print the embedded Familiar harness model and effort catalog.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/familiar-harness.sh"

usage() {
  printf 'Usage: %s --harness <harness> [--efforts | --intent <planning|implementation|review>]\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

main() {
  local harness=''
  local harness_seen=0
  local show_efforts=0
  local intent=''

  while (($#)); do
    case "$1" in
      --harness)
        (($# >= 2)) || fail 'Missing value for --harness'
        (( ! harness_seen )) || fail '--harness may be specified once'
        [[ -n $2 && $2 != --* ]] || fail '--harness requires one non-empty value'
        harness=$2
        harness_seen=1
        shift 2
        ;;
      --efforts)
        (( ! show_efforts )) || fail '--efforts may be specified once'
        show_efforts=1
        shift
        ;;
      --intent)
        (($# >= 2)) || fail 'Missing value for --intent'
        [[ -z $intent && -n $2 && $2 != --* ]] || fail '--intent requires one non-empty value and may be specified once'
        intent=$2
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        usage
        fail "Unknown option: $1"
        ;;
    esac
  done

  [[ -n $harness ]] || {
    usage
    fail 'The --harness option is required.'
  }
  familiar_harness_load "$harness" || exit 1
  if [[ -n $intent ]] && (( show_efforts )); then
    fail 'Choose either --efforts or --intent.'
  fi

  if [[ -n $intent ]]; then
    if ! familiar_harness_intent_pair "$intent"; then
      fail "Unknown intent for Familiar harness $harness: $intent (expected planning, implementation, or review)"
    fi
  elif (( show_efforts )); then
    familiar_harness_efforts
  else
    familiar_harness_models
  fi
}

main "$@"
