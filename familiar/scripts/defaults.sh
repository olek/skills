#!/usr/bin/env bash
# Print the configured model and effort pair for a Familiar intent.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/harness.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/intent-config.sh"

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
  local configuration
  local configuration_path
  local configured_pair
  local candidate_intent
  local config_status
  local missing_intents=''

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
  [[ $intent == planning || $intent == implementation || $intent == review ]] || \
    fail "Unknown Familiar intent: $intent (expected planning, implementation, or review)"
  familiar_harness_load "$harness" || exit 1
  familiar_ensure_home_layout || fail 'Could not create the Familiar home layout.'
  configuration_path=$(familiar_intent_config_path) || fail 'Could not resolve the Familiar intent configuration path.'
  configuration=present
  [[ -e $configuration_path ]] || configuration=missing
  pair='default default'
  for candidate_intent in planning implementation review; do
    if configured_pair=$(familiar_intent_config_pair "$harness" "$candidate_intent"); then
      [[ $candidate_intent != "$intent" ]] || pair=$configured_pair
    else
      config_status=$?
      if (( config_status > 1 )); then
        exit "$config_status"
      fi
      [[ -z $missing_intents ]] || missing_intents+=,
      missing_intents+=$candidate_intent
    fi
  done
  readonly pair
  read -r model effort extra <<< "$pair"
  readonly model effort extra
  [[ -n $model && -n $effort && -z ${extra:-} ]] || fail "Invalid default pair for Familiar harness $harness and intent $intent"
  printf 'model=%s\neffort=%s\nconfiguration=%s\nmissing_intents=%s\nconfiguration_path=%s\n' \
    "$model" "$effort" "$configuration" "$missing_intents" "$configuration_path"
}

main "$@"
