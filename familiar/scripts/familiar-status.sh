#!/usr/bin/env bash
# Report the Familiar managed by the current summoning agent instance.
#
# The launcher stores the name, launch timestamp, harness, canonical Familiar
# home, and summoning pane on the Familiar pane. This script derives the
# request and response paths and reports delivery or termination state.
#
# Run this from the summoning agent's pane. It uses TMUX_PANE as the stable
# identity of that agent instance, so moving between windows does not redirect
# the query. By default it reports immediately. Use --wait [--timeout <seconds>]
# to wait quietly for a response; the default timeout is ten minutes.  Add
# --auto-close to keep waiting in the same invocation after delivery for a
# configurable inspection interval (60 seconds by default), closing the Familiar
# pane if it remains open. FAMILIAR_AUTO_CLOSE_SECONDS controls the interval.
# The launcher permits one managed Familiar per summoning agent instance.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY
readonly DEFAULT_WAIT_TIMEOUT_SECONDS=600
readonly POLL_INTERVAL_SECONDS=5
readonly DEFAULT_AUTO_CLOSE_SECONDS=60
readonly AUTO_CLOSE_POLL_INTERVAL_SECONDS=1

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/familiar-config.sh"

usage() {
  printf 'Usage: %s [--wait] [--timeout <seconds>] [--auto-close]\n' "${0##*/}" >&2
  printf '       FAMILIAR_AUTO_CLOSE_SECONDS sets the default auto-close interval; default: 60\n' >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

normalize_auto_close_seconds() {
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
  local -n wait_for_completion_ref=$1
  local -n wait_option_seen_ref=$2
  local -n timeout_seconds_ref=$3
  local -n auto_close_enabled_ref=$4
  shift 4

  while (($#)); do
    case "$1" in
      --wait)
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        wait_for_completion_ref=1
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        wait_option_seen_ref=1
        shift
        ;;
      --timeout)
        (($# >= 2)) || fail 'Missing value for --timeout'
        [[ $2 =~ ^[0-9]+$ ]] || fail '--timeout must be a non-negative integer number of seconds'
        # shellcheck disable=SC2034 # These namerefs return the values to main.
        wait_for_completion_ref=1
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        timeout_seconds_ref=$((10#$2))
        shift 2
        ;;
      --auto-close)
        (( ! auto_close_enabled_ref )) || fail '--auto-close may be specified once'
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        auto_close_enabled_ref=1
        if (($# >= 2)) && [[ $2 != --* ]]; then
          fail '--auto-close does not take a value; set FAMILIAR_AUTO_CLOSE_SECONDS instead'
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

  (( ! auto_close_enabled_ref || wait_option_seen_ref )) || fail '--auto-close requires --wait; use --wait --auto-close.'
}

managed_familiar_rows() {
  local -r summoner_pane=$1

  # Each row contains pane ID, name, timestamp, harness, home, and dead flag.
  tmux list-panes -a -F $'#{pane_id}\t#{@familiar}\t#{@familiar_name}\t#{@familiar_timestamp}\t#{@familiar_harness}\t#{@familiar_home}\t#{@familiar_summoner_pane}\t#{pane_dead}' \
    | awk -F '\t' -v summoner="$summoner_pane" '
      $2 == "1" && $7 == summoner {
        harness = $5
        if (harness == "") {
          harness = "codex"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $3, $4, harness, $6, $8
      }'
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
  local -r pane_id=$3

  printf 'Managed Familiar: %s (%s, pane %s, invalid metadata)\n' \
    "$familiar_name" "$familiar_harness" "$pane_id"
  printf '  request: unavailable\n  response: unavailable\n'
}

report_familiars() {
  local -r summoner_pane=$1
  local pane_id
  local familiar_name
  local familiar_timestamp
  local familiar_harness
  local storage_directory
  local pane_dead
  local request_file
  local response_file
  local derived_paths
  local found_familiar=0

  while IFS=$'\t' read -r pane_id familiar_name familiar_timestamp familiar_harness storage_directory pane_dead; do
    [[ $pane_id ]] || continue
    found_familiar=1

    if ! derived_paths=$(derive_paths "$familiar_timestamp" "$familiar_name" "$storage_directory"); then
      report_invalid_metadata "$familiar_name" "$familiar_harness" "$pane_id"
      continue
    fi
    IFS=$'\t' read -r request_file response_file <<< "$derived_paths"

    if [[ $pane_dead == 1 && ! -f $response_file ]]; then
      printf 'Managed Familiar: %s (%s, pane %s, ended without response)\n' \
        "$familiar_name" "$familiar_harness" "$pane_id"
    else
      printf 'Managed Familiar: %s (%s, pane %s, %s)\n' \
        "$familiar_name" "$familiar_harness" "$pane_id" "$(response_status "$response_file")"
    fi
    printf '  request: %s\n  response: %s\n' "$request_file" "$response_file"
  done < <(managed_familiar_rows "$summoner_pane")

  if (( ! found_familiar )); then
    printf 'No managed Familiar exists for this summoning agent instance.\n'
  fi
}

completion_state() {
  local -r summoner_pane=$1
  local pane_id
  local familiar_name
  local familiar_timestamp
  local familiar_harness
  local storage_directory
  local pane_dead
  local derived_paths
  local response_file
  local found_familiar=0
  local awaiting_response=0
  local failed_familiar=0

  while IFS=$'\t' read -r pane_id familiar_name familiar_timestamp familiar_harness storage_directory pane_dead; do
    [[ $pane_id ]] || continue
    found_familiar=1

    if ! derived_paths=$(derive_paths "$familiar_timestamp" "$familiar_name" "$storage_directory"); then
      failed_familiar=1
      continue
    fi
    IFS=$'\t' read -r _ response_file <<< "$derived_paths"

    if [[ -f $response_file ]]; then
      continue
    fi
    if [[ -e $response_file || $pane_dead == 1 ]]; then
      failed_familiar=1
    else
      awaiting_response=1
    fi
  done < <(managed_familiar_rows "$summoner_pane")

  if (( ! found_familiar )); then
    printf 'no-familiar'
  elif (( failed_familiar )); then
    printf 'failed'
  elif (( awaiting_response )); then
    printf 'waiting'
  else
    printf 'delivered'
  fi
}

open_familiar_pane_id() {
  local -r summoner_pane=$1

  managed_familiar_rows "$summoner_pane" \
    | awk -F '\t' '$6 != "1" { print $1; exit }'
}

wait_for_auto_close() {
  local -r summoner_pane=$1
  local -r inspection_seconds=$2
  local started_at_seconds=$SECONDS
  local pane_id
  local remaining_seconds
  local sleep_seconds

  while true; do
    pane_id=$(open_familiar_pane_id "$summoner_pane")
    if [[ -z $pane_id ]]; then
      printf 'Auto-close ended: the Familiar pane is closed.\n'
      return 0
    fi

    remaining_seconds=$((inspection_seconds - (SECONDS - started_at_seconds)))
    if (( remaining_seconds <= 0 )); then
      if tmux kill-pane -t "$pane_id"; then
        printf 'Auto-closed Familiar pane %s after %s seconds of user inspection.\n' "$pane_id" "$inspection_seconds"
      else
        printf 'Auto-close ended: the Familiar pane was already closed.\n'
      fi
      return 0
    fi
    sleep_seconds=$AUTO_CLOSE_POLL_INTERVAL_SECONDS
    if (( remaining_seconds < sleep_seconds )); then
      sleep_seconds=$remaining_seconds
    fi
    sleep "$sleep_seconds"
  done
}

wait_for_completion() {
  local -r summoner_pane=$1
  local -r timeout_seconds=$2
  local -r auto_close_enabled=$3
  local -r auto_close_seconds=$4
  local started_at_seconds=$SECONDS
  local state
  local remaining_seconds
  local sleep_seconds

  while true; do
    state=$(completion_state "$summoner_pane")
    case "$state" in
      delivered)
        if (( auto_close_enabled )); then
          wait_for_auto_close "$summoner_pane" "$auto_close_seconds"
        fi
        report_familiars "$summoner_pane"
        return
        ;;
      failed|no-familiar)
        report_familiars "$summoner_pane"
        return
        ;;
      waiting)
        remaining_seconds=$((timeout_seconds - (SECONDS - started_at_seconds)))
        if (( remaining_seconds <= 0 )); then
          report_familiars "$summoner_pane"
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
  local wait_for_completion=0
  # shellcheck disable=SC2034 # Passed by nameref to parse_arguments.
  local wait_option_seen=0
  local timeout_seconds=$DEFAULT_WAIT_TIMEOUT_SECONDS
  local auto_close_enabled=0
  local auto_close_seconds=${FAMILIAR_AUTO_CLOSE_SECONDS:-$DEFAULT_AUTO_CLOSE_SECONDS}

  parse_arguments wait_for_completion wait_option_seen timeout_seconds auto_close_enabled "$@"
  if (( auto_close_enabled )); then
    auto_close_seconds=$(normalize_auto_close_seconds "$auto_close_seconds" 'FAMILIAR_AUTO_CLOSE_SECONDS')
  fi
  [[ -n ${TMUX:-} ]] || fail 'This status command must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This status command must run from a tmux pane.'
  if (( wait_for_completion )); then
    wait_for_completion "$TMUX_PANE" "$timeout_seconds" "$auto_close_enabled" "$auto_close_seconds"
  else
    report_familiars "$TMUX_PANE"
  fi
}

main "$@"
