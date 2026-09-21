#!/usr/bin/env bash
# Print the model and effort pair suggested for a Familiar intent.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/harness.sh"

usage() {
  printf 'Usage: %s --harness <harness> --intent <planning|implementation|review>\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

main() {
  local harness=''
  local intent=''
  local pair
  local model
  local effort
  local extra

  while (($#)); do
    case "$1" in
      --harness)
        (($# >= 2)) || fail 'Missing value for --harness'
        [[ -z $harness && -n $2 ]] || fail '--harness requires one non-empty value and may be specified once'
        harness=$2
        shift 2
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

  readonly harness intent
  [[ -n $harness ]] || {
    usage
    fail 'The --harness option is required.'
  }
  [[ -n $intent ]] || {
    usage
    fail 'The --intent option is required.'
  }
  familiar_harness_load "$harness" || exit 1
  if ! pair=$(familiar_harness_intent_pair "$intent"); then
    fail "Unknown intent for Familiar harness $harness: $intent (expected planning, implementation, or review)"
  fi
  readonly pair
  read -r model effort extra <<< "$pair"
  readonly model effort extra
  [[ -n $model && -n $effort && -z ${extra:-} ]] || fail "Invalid default pair for Familiar harness $harness and intent $intent"
  printf 'model=%s\neffort=%s\n' "$model" "$effort"
}

main "$@"
