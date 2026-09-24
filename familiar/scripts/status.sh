#!/usr/bin/env bash
# Report the Familiar managed by the current summoning agent instance.
#
# The launcher stores the name, launch timestamp, harness, canonical Familiar
# home, and summoner on the Familiar. This script derives the
# request and response paths and reports delivery or termination state.
#
# Run this from the summoning agent's terminal. The backend supplies its stable
# identity, so moving between terminal views does not redirect the query. By
# default it reports immediately. Use --wait [--timeout <seconds>]
# to wait quietly for a response; the default timeout is ten minutes.  Add
# --auto-dismiss to keep waiting in the same invocation after delivery for a
# configurable inspection interval (60 seconds by default), closing the Familiar
# pane if it remains open. FAMILIAR_AUTO_DISMISS_SECONDS controls the interval.
# The launcher permits one managed Familiar per summoning agent instance.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY
readonly DEFAULT_WAIT_TIMEOUT_SECONDS=600
readonly POLL_INTERVAL_SECONDS=5
readonly DEFAULT_AUTO_DISMISS_SECONDS=60
readonly AUTO_DISMISS_POLL_INTERVAL_SECONDS=1

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/harness.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/backend.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/familiar.sh"

usage() {
  printf 'Usage: %s [--wait] [--timeout <seconds>] [--auto-dismiss]\n' "${0##*/}" >&2
  printf '       FAMILIAR_AUTO_DISMISS_SECONDS sets the default auto-dismiss interval; default: 60\n' >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

normalize_auto_dismiss_seconds() {
  local -r value=$1
  local -r source_name=$2

  [[ $value =~ ^[0-9]+$ ]] || fail "$source_name must be a non-negative integer number of seconds"
  (( 10#$value <= 60 )) || fail "$source_name must be no more than 60 seconds"
  printf '%d\n' "$((10#$value))"
}

response_status() {
  local -r response_file=$1

  if [[ -f $response_file ]]; then
    printf 'response delivered'
  elif [[ -e $response_file ]]; then
    printf 'response path invalid'
  else
    printf 'awaiting response'
  fi
}

parse_arguments() {
  local -n should_wait_ref=$1
  local -n wait_option_seen_ref=$2
  local -n timeout_seconds_ref=$3
  local -n auto_dismiss_enabled_ref=$4
  shift 4

  while (($#)); do
    case "$1" in
      --wait)
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        should_wait_ref=1
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        wait_option_seen_ref=1
        shift
        ;;
      --timeout)
        (($# >= 2)) || fail 'Missing value for --timeout'
        [[ $2 =~ ^[0-9]+$ ]] || fail '--timeout must be a non-negative integer number of seconds'
        # shellcheck disable=SC2034 # These namerefs return the values to main.
        should_wait_ref=1
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        timeout_seconds_ref=$((10#$2))
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

  (( ! auto_dismiss_enabled_ref || wait_option_seen_ref )) || fail '--auto-dismiss requires --wait; use --wait --auto-dismiss.'
}

derive_paths() {
  local -r familiar_timestamp=$1
  local -r familiar_name=$2
  local -r storage_directory=$3

  familiar_validate_name "$familiar_name" || return 1
  familiar_validate_timestamp "$familiar_timestamp" || return 1
  familiar_validate_storage_directory "$storage_directory" || return 1
  printf '%s\t%s\n' \
    "$(familiar_path_in_directory "$storage_directory" "$(familiar_request_filename "$familiar_timestamp" "$familiar_name")")" \
    "$(familiar_path_in_directory "$storage_directory" "$(familiar_response_filename "$familiar_timestamp" "$familiar_name")")"
}

report_invalid_metadata() {
  local -r familiar_name=$1
  local -r familiar_harness=$2
  local -r familiar_id=$3

  printf 'Managed Familiar: %s (%s, pane %s, invalid metadata)\n' \
    "$familiar_name" "$familiar_harness" "$familiar_id"
  printf '  request: unavailable\n  response: unavailable\n'
}

report_familiars() {
  local -r summoner_id=$1
  local familiar_id
  local familiar_name
  local familiar_timestamp
  local familiar_harness
  local storage_directory
  local familiar_closed
  local request_file
  local response_file
  local derived_paths
  local has_managed_familiar=0

  while IFS=$'\t' read -r familiar_id familiar_name familiar_timestamp familiar_harness storage_directory familiar_closed; do
    [[ $familiar_id ]] || continue
    has_managed_familiar=1

    if ! derived_paths=$(derive_paths "$familiar_timestamp" "$familiar_name" "$storage_directory"); then
      report_invalid_metadata "$familiar_name" "$familiar_harness" "$familiar_id"
      continue
    fi
    IFS=$'\t' read -r request_file response_file <<< "$derived_paths"

    if [[ $familiar_closed == 1 && ! -f $response_file ]]; then
      printf 'Managed Familiar: %s (%s, pane %s, ended without response)\n' \
        "$familiar_name" "$familiar_harness" "$familiar_id"
    else
      printf 'Managed Familiar: %s (%s, pane %s, %s)\n' \
        "$familiar_name" "$familiar_harness" "$familiar_id" "$(response_status "$response_file")"
    fi
    printf '  request: %s\n  response: %s\n' "$request_file" "$response_file"
  done < <(familiar_managed_familiars "$summoner_id")

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
  local storage_directory
  local familiar_closed
  local derived_paths
  local response_file
  local has_managed_familiar=0
  local has_pending_response=0
  local has_failure=0

  while IFS=$'\t' read -r familiar_id familiar_name familiar_timestamp familiar_harness storage_directory familiar_closed; do
    [[ $familiar_id ]] || continue
    has_managed_familiar=1

    if ! derived_paths=$(derive_paths "$familiar_timestamp" "$familiar_name" "$storage_directory"); then
      has_failure=1
      continue
    fi
    IFS=$'\t' read -r _ response_file <<< "$derived_paths"

    if [[ -f $response_file ]]; then
      continue
    fi
    if [[ -e $response_file || $familiar_closed == 1 ]]; then
      has_failure=1
    else
      has_pending_response=1
    fi
  done < <(familiar_managed_familiars "$summoner_id")

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

  familiar_managed_familiars "$summoner_id" \
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
      printf 'Auto-dismiss ended: the Familiar pane is closed.\n'
      return 0
    fi

    remaining_seconds=$((inspection_seconds - (SECONDS - started_at_seconds)))
    if (( remaining_seconds <= 0 )); then
      if familiar_close_familiar "$familiar_id"; then
        printf 'Auto-dismissed Familiar pane %s after %s seconds of user inspection.\n' "$familiar_id" "$inspection_seconds"
      else
        printf 'Auto-dismiss ended: the Familiar pane was already closed.\n'
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
  # shellcheck disable=SC2034 # Passed by nameref to parse_arguments.
  local wait_option_seen=0
  local timeout_seconds=$DEFAULT_WAIT_TIMEOUT_SECONDS
  local auto_dismiss_enabled=0
  local auto_dismiss_seconds=${FAMILIAR_AUTO_DISMISS_SECONDS:-$DEFAULT_AUTO_DISMISS_SECONDS}

  parse_arguments should_wait wait_option_seen timeout_seconds auto_dismiss_enabled "$@"
  if (( auto_dismiss_enabled )); then
    auto_dismiss_seconds=$(normalize_auto_dismiss_seconds "$auto_dismiss_seconds" 'FAMILIAR_AUTO_DISMISS_SECONDS')
  fi
  readonly should_wait timeout_seconds auto_dismiss_enabled auto_dismiss_seconds
  local summoner_id
  familiar_backend_require_context || exit 1
  summoner_id=$(familiar_backend_summoner_id)
  readonly summoner_id
  if (( should_wait )); then
    wait_for_completion "$summoner_id" "$timeout_seconds" "$auto_dismiss_enabled" "$auto_dismiss_seconds"
  else
    report_familiars "$summoner_id"
  fi
}

main "$@"
