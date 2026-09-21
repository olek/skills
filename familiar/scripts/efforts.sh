#!/usr/bin/env bash
# Print one supported Familiar harness effort ID per line.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/harness.sh"

usage() {
  printf 'Usage: %s --harness <harness>\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

main() {
  local harness=''

  while (($#)); do
    case "$1" in
      --harness)
        (($# >= 2)) || fail 'Missing value for --harness'
        [[ -z $harness && -n $2 ]] || fail '--harness requires one non-empty value and may be specified once'
        harness=$2
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

  readonly harness
  [[ -n $harness ]] || {
    usage
    fail 'The --harness option is required.'
  }
  familiar_harness_load "$harness" || exit 1
  familiar_harness_efforts
}

main "$@"
