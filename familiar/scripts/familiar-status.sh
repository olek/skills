#!/usr/bin/env bash
# Report managed Familiars for the requesting pane's tmux window.
#
# The launcher stores identifying metadata and request and response paths on its
# Familiar's pane.  This script reads that metadata to show each Familiar's name,
# target harness, pane, request, response location, and response/termination
# state.  It does not inspect ordinary tmux panes or headless sub-agents
# launched outside this skill.
#
# Run this from the pane whose managed Familiars you want to check.  It uses
# TMUX_PANE to target that pane's window rather than the active tmux client, so
# changing windows or sessions while the command is pending does not redirect
# the query.  By default it reports immediately.  Use --wait [--timeout
# seconds] to wait quietly for a response; the default timeout is ten minutes
# and the script prints only one final report.  It reports every managed Familiar
# pane found in that window, though the launcher normally permits only one.
set -euo pipefail

readonly DEFAULT_WAIT_TIMEOUT_SECONDS=600
readonly POLL_INTERVAL_SECONDS=5

usage() {
  printf 'Usage: %s [--wait] [--timeout <seconds>]\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
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
  local -n timeout_seconds_ref=$2
  shift 2

  while (($#)); do
    case "$1" in
      --wait)
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        wait_for_completion_ref=1
        shift
        ;;
      --timeout)
        (($# >= 2)) || fail 'Missing value for --timeout'
        [[ $2 =~ ^[0-9]+$ ]] || fail '--timeout must be a non-negative integer number of seconds'
        # shellcheck disable=SC2034 # These namerefs return the values to main.
        wait_for_completion_ref=1
        # shellcheck disable=SC2034 # This nameref returns the value to main.
        timeout_seconds_ref=$2
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
}

managed_familiar_rows() {
  local -r window_id=$1

  # Each row is a managed Familiar pane's metadata: the marker flag, name,
  # harness, task and response paths, then the pane's dead flag.
  tmux list-panes -t "$window_id" -F $'#{pane_id}\t#{@familiar}\t#{@familiar_name}\t#{@familiar_harness}\t#{@familiar_task}\t#{@familiar_response}\t#{pane_dead}' \
    | awk -F '\t' '
      $2 == "1" {
        harness = $4
        if (harness == "") {
          harness = "codex"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $3, harness, $5, $6, $7
      }'
}

report_familiars() {
  local -r window_id=$1
  local pane_id
  local familiar_name
  local familiar_harness
  local request_file
  local response_file
  local pane_dead
  local found_familiar=0

  while IFS=$'\t' read -r pane_id familiar_name familiar_harness request_file response_file pane_dead; do
    [[ $pane_id ]] || continue
    found_familiar=1

    if [[ $pane_dead == 1 && ! -f $response_file ]]; then
      printf 'Managed Familiar: %s (%s, pane %s, ended without response)\n' \
        "$familiar_name" "$familiar_harness" "$pane_id"
    else
      printf 'Managed Familiar: %s (%s, pane %s, %s)\n' \
        "$familiar_name" "$familiar_harness" "$pane_id" "$(response_status "$response_file")"
    fi
    printf '  request: %s\n  response: %s\n' "$request_file" "$response_file"
  done < <(managed_familiar_rows "$window_id")

  if (( ! found_familiar )); then
    printf 'No managed Familiar exists in the requesting tmux window.\n'
  fi
}

completion_state() {
  local -r window_id=$1
  local pane_id
  local familiar_name
  local familiar_harness
  local request_file
  local response_file
  local pane_dead
  local found_familiar=0
  local awaiting_response=0
  local failed_familiar=0

  while IFS=$'\t' read -r pane_id familiar_name familiar_harness request_file response_file pane_dead; do
    [[ $pane_id ]] || continue
    found_familiar=1

    if [[ -f $response_file ]]; then
      continue
    fi
    if [[ -e $response_file || $pane_dead == 1 ]]; then
      failed_familiar=1
    else
      awaiting_response=1
    fi
  done < <(managed_familiar_rows "$window_id")

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

wait_for_completion() {
  local -r window_id=$1
  local -r timeout_seconds=$2
  local started_at_seconds=$SECONDS
  local state
  local remaining_seconds
  local sleep_seconds

  while true; do
    state=$(completion_state "$window_id")
    case "$state" in
      delivered|failed|no-familiar)
        report_familiars "$window_id"
        return
        ;;
      waiting)
        remaining_seconds=$((timeout_seconds - (SECONDS - started_at_seconds)))
        if (( remaining_seconds <= 0 )); then
          report_familiars "$window_id"
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
  local window_id
  local wait_for_completion=0
  local timeout_seconds=$DEFAULT_WAIT_TIMEOUT_SECONDS

  parse_arguments wait_for_completion timeout_seconds "$@"
  [[ -n ${TMUX:-} ]] || fail 'This status command must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This status command must run from a tmux pane.'
  window_id=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
  readonly window_id

  if (( wait_for_completion )); then
    wait_for_completion "$window_id" "$timeout_seconds"
  else
    report_familiars "$window_id"
  fi
}

main "$@"
