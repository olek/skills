#!/usr/bin/env bash
# Report delivery and optionally wait for the current Familiar.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY
readonly DEFAULT_WAIT_TIMEOUT_SECONDS=600
readonly POLL_INTERVAL_SECONDS=5
readonly MAX_AUTO_DISMISS_SECONDS=60
readonly DEFAULT_AUTO_DISMISS_SECONDS=$MAX_AUTO_DISMISS_SECONDS
readonly AUTO_DISMISS_POLL_INTERVAL_SECONDS=1

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/backend.sh"

usage() {
  printf 'Usage: %s [--wait [--timeout <seconds>] [--auto-dismiss]]\n' "${0##*/}" >&2
  printf '       FAMILIAR_AUTO_DISMISS_SECONDS sets the auto-dismiss interval; default and maximum: %s\n' "$MAX_AUTO_DISMISS_SECONDS" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

normalize_auto_dismiss_seconds() {
  local -r value=$1

  [[ $value =~ ^[0-9]+$ ]] || fail "FAMILIAR_AUTO_DISMISS_SECONDS must be a non-negative integer number of seconds"
  (( 10#$value <= MAX_AUTO_DISMISS_SECONDS )) || fail "FAMILIAR_AUTO_DISMISS_SECONDS must be no more than $MAX_AUTO_DISMISS_SECONDS seconds"
  printf '%d\n' "$((10#$value))"
}

familiar_row_state() {
  local -r timestamp=$1 name=$2 home=$3 closed=$4
  local paths request response
  paths=$(familiar_summoning_paths "$home" "$timestamp" "$name") || {
    printf invalid-metadata
    return
  }
  IFS=$'\t' read -r _ request response <<< "$paths"
  if [[ -f $response ]]; then
    printf delivered
  elif [[ $closed == 1 ]]; then
    printf aborted
  elif [[ -e $response ]]; then
    printf invalid
  else
    printf awaiting
  fi
}

parse_arguments() {
  local -n should_wait_ref=$1
  local -n timeout_seconds_ref=$2
  local -n auto_dismiss_enabled_ref=$3
  shift 3
  local timeout_seen=0

  while (($#)); do
    case "$1" in
      --wait)
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        should_wait_ref=1
        shift
        ;;
      --timeout)
        (($# >= 2)) || fail 'Missing value for --timeout'
        [[ $2 =~ ^[0-9]+$ ]] || fail '--timeout must be a non-negative integer number of seconds'
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        timeout_seconds_ref=$((10#$2))
        timeout_seen=1
        shift 2
        ;;
      --auto-dismiss)
        (( ! auto_dismiss_enabled_ref )) || fail '--auto-dismiss may be specified once'
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        auto_dismiss_enabled_ref=1
        if (($# >= 2)) && [[ $2 != --* ]]; then
          fail '--auto-dismiss does not take a value; set FAMILIAR_AUTO_DISMISS_SECONDS instead'
        fi
        shift
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

  (( should_wait_ref )) || {
    (( ! timeout_seen )) || fail '--timeout requires --wait; use --wait --timeout <seconds>.'
    (( ! auto_dismiss_enabled_ref )) || fail '--auto-dismiss requires --wait; use --wait --auto-dismiss.'
  }
}

derive_paths() {
  local paths request response
  paths=$(familiar_summoning_paths "$3" "$1" "$2") || return 1
  IFS=$'\t' read -r _ request response <<< "$paths"
  printf '%s\t%s\n' "$request" "$response"
}

report_invalid_metadata() {
  local -r familiar_name=$1
  local -r familiar_harness=$2
  local -r familiar_id=$3

  printf 'Managed Familiar: %s (%s, %s %s, invalid metadata)\n' \
    "$familiar_name" "$familiar_harness" "$(familiar_backend_display_noun)" "$familiar_id"
  printf '  request: unavailable\n  response: unavailable\n'
}

report_familiars() {
  local -r summoner_id=$1
  local familiar_id
  local familiar_name
  local familiar_timestamp
  local familiar_harness
  local home
  local familiar_closed
  local request_file
  local response_file
  local derived_paths
  local has_managed_familiar=0
  local familiars

  familiars=$(familiar_backend_list_familiars "$summoner_id") || return 1

  while IFS=$'\t' read -r familiar_id familiar_name familiar_timestamp familiar_harness home familiar_closed; do
    [[ $familiar_id ]] || continue
    has_managed_familiar=1

    local row_state label
    row_state=$(familiar_row_state "$familiar_timestamp" "$familiar_name" "$home" "$familiar_closed")
    if [[ $row_state == invalid-metadata ]]; then
      report_invalid_metadata "$familiar_name" "$familiar_harness" "$familiar_id"
      continue
    fi
    derived_paths=$(derive_paths "$familiar_timestamp" "$familiar_name" "$home")
    IFS=$'\t' read -r request_file response_file <<< "$derived_paths"
    case "$row_state" in
      delivered) label='response delivered' ;;
      aborted) label='aborted without response' ;;
      invalid) label='response path invalid' ;;
      awaiting) label='awaiting response' ;;
    esac
    printf 'Managed Familiar: %s (%s, %s %s, %s)\n' \
      "$familiar_name" "$familiar_harness" "$(familiar_backend_display_noun)" "$familiar_id" "$label"
    printf '  request: %s\n  response: %s\n' "$request_file" "$response_file"
  done <<< "$familiars"

  if (( ! has_managed_familiar )); then
    printf 'No managed Familiar exists for this summoning agent instance.\n'
  fi
}

completion_state() {
  local -r summoner_id=$1
  local familiar_id
  local familiar_name
  local familiar_timestamp
  local familiar_harness
  local home
  local familiar_closed
  local has_managed_familiar=0
  local has_pending_response=0
  local has_failure=0
  local familiars

  familiars=$(familiar_backend_list_familiars "$summoner_id") || return 1

  while IFS=$'\t' read -r familiar_id familiar_name familiar_timestamp familiar_harness home familiar_closed; do
    [[ $familiar_id ]] || continue
    has_managed_familiar=1

    local row_state
    row_state=$(familiar_row_state "$familiar_timestamp" "$familiar_name" "$home" "$familiar_closed")
    case "$row_state" in
      aborted|invalid|invalid-metadata) has_failure=1 ;;
      awaiting) has_pending_response=1 ;;
    esac
  done <<< "$familiars"

  if (( ! has_managed_familiar )); then
    printf 'no-familiar'
  elif (( has_failure )); then
    printf 'failed'
  elif (( has_pending_response )); then
    printf 'waiting'
  else
    printf 'delivered'
  fi
}

open_familiar_id() {
  local -r summoner_id=$1

  familiar_backend_list_familiars "$summoner_id" \
    | awk -F '\t' '$6 != "1" { print $1; exit }'
}

wait_for_auto_dismiss() {
  local -r summoner_id=$1
  local -r inspection_seconds=$2
  local -r started_at_seconds=$SECONDS
  local familiar_id
  local remaining_seconds
  local sleep_seconds

  while true; do
    familiar_id=$(open_familiar_id "$summoner_id")
    if [[ -z $familiar_id ]]; then
      printf 'Auto-dismiss ended: the Familiar %s is closed.\n' "$(familiar_backend_display_noun)"
      return 0
    fi

    remaining_seconds=$((inspection_seconds - (SECONDS - started_at_seconds)))
    if (( remaining_seconds <= 0 )); then
      if familiar_backend_close_familiar "$familiar_id"; then
        printf 'Auto-dismissed Familiar %s %s after %s seconds of user inspection.\n' "$(familiar_backend_display_noun)" "$familiar_id" "$inspection_seconds"
      else
        printf 'Auto-dismiss ended: the Familiar %s was already closed.\n' "$(familiar_backend_display_noun)"
      fi
      return 0
    fi
    sleep_seconds=$AUTO_DISMISS_POLL_INTERVAL_SECONDS
    if (( remaining_seconds < sleep_seconds )); then
      sleep_seconds=$remaining_seconds
    fi
    sleep "$sleep_seconds"
  done
}

wait_for_completion() {
  local -r summoner_id=$1
  local -r timeout_seconds=$2
  local -r auto_dismiss_enabled=$3
  local -r auto_dismiss_seconds=$4
  local -r started_at_seconds=$SECONDS
  local state
  local remaining_seconds
  local sleep_seconds

  while true; do
    state=$(completion_state "$summoner_id")
    case "$state" in
      delivered)
        if (( auto_dismiss_enabled )); then
          wait_for_auto_dismiss "$summoner_id" "$auto_dismiss_seconds"
        fi
        report_familiars "$summoner_id"
        return
        ;;
      failed|no-familiar)
        report_familiars "$summoner_id"
        return
        ;;
      waiting)
        remaining_seconds=$((timeout_seconds - (SECONDS - started_at_seconds)))
        if (( remaining_seconds <= 0 )); then
          report_familiars "$summoner_id"
          printf 'Timed out after %s seconds; the Familiar is still working.\n' "$timeout_seconds"
          return
        fi
        sleep_seconds=$POLL_INTERVAL_SECONDS
        if (( remaining_seconds < sleep_seconds )); then
          sleep_seconds=$remaining_seconds
        fi
        sleep "$sleep_seconds"
        ;;
      *)
        fail "Unexpected completion state: $state"
        ;;
    esac
  done
}

main() {
  local should_wait=0
  local timeout_seconds=$DEFAULT_WAIT_TIMEOUT_SECONDS
  local auto_dismiss_enabled=0
  local auto_dismiss_seconds=${FAMILIAR_AUTO_DISMISS_SECONDS:-$DEFAULT_AUTO_DISMISS_SECONDS}

  parse_arguments should_wait timeout_seconds auto_dismiss_enabled "$@"
  if (( auto_dismiss_enabled )); then
    auto_dismiss_seconds=$(normalize_auto_dismiss_seconds "$auto_dismiss_seconds")
  fi
  readonly should_wait timeout_seconds auto_dismiss_enabled auto_dismiss_seconds
  local summoner_id
  summoner_id=$(familiar_current_summoner_id) || exit 1
  readonly summoner_id
  if (( should_wait )); then
    wait_for_completion "$summoner_id" "$timeout_seconds" "$auto_dismiss_enabled" "$auto_dismiss_seconds"
  else
    report_familiars "$summoner_id"
  fi
}

main "$@"
