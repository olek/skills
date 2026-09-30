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
  local configured_pair
  local model
  local effort
  local configuration
  local configuration_path
  local entries
  local entry_intent entry_model entry_effort
  local candidate_intent
  local config_status
  local missing_intents=''
  local home

  while (($#)); do
    case "$1" in
      --harness)
        (($# >= 2)) || fail 'Missing value for --harness'
        [[ -z $harness && -n $2 && $2 != --* ]] || fail '--harness requires one non-empty value and may be specified once'
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
  [[ " ${FAMILIAR_INTENTS[*]} " == *" $intent "* ]] || {
    local IFS=,
    fail "Unknown Familiar intent: $intent (expected ${FAMILIAR_INTENTS[*]})"
  }
  familiar_harness_load "$harness" || exit 1
  home=$(familiar_home) || exit 1
  familiar_ensure_home_layout "$home" || fail 'Could not create the Familiar home layout.'
  configuration_path=$(familiar_intent_config_path) || fail 'Could not resolve the Familiar intent configuration path.'
  configuration=present
  [[ -e $configuration_path ]] || configuration=missing
  pair='default default'
  if entries=$(familiar_intent_config_entries "$harness"); then
    :
  else
    config_status=$?
    (( config_status == 1 )) || exit "$config_status"
    entries=''
  fi
  for candidate_intent in "${FAMILIAR_INTENTS[@]}"; do
    configured_pair=''
    while IFS=$'\t' read -r entry_intent entry_model entry_effort; do
      if [[ $entry_intent == "$candidate_intent" ]]; then
        configured_pair="$entry_model $entry_effort"
        break
      fi
    done <<< "$entries"
    if [[ -n $configured_pair ]]; then
      [[ $candidate_intent != "$intent" ]] || pair=$configured_pair
    else
      [[ -z $missing_intents ]] || missing_intents+=,
      missing_intents+=$candidate_intent
    fi
  done
  readonly pair
  read -r model effort <<< "$pair"
  readonly model effort
  printf 'model=%s\neffort=%s\nconfiguration=%s\nmissing_intents=%s\nconfiguration_path=%s\n' \
    "$model" "$effort" "$configuration" "$missing_intents" "$configuration_path"
}

main "$@"
