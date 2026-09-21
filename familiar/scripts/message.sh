#!/usr/bin/env bash
# Send one message to the live Familiar managed by the current summoning pane.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY
readonly MESSAGE_SUBMISSION_DELAY_SECONDS=0.1

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/pane.sh"

usage() {
  printf 'Usage: %s --message <text>\n' "${0##*/}" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

parse_arguments() {
  local -n message_ref=$1
  local -n message_seen_ref=$2
  shift 2

  while (($#)); do
    case "$1" in
      --message)
        (($# >= 2)) || fail 'Missing value for --message'
        (( ! message_seen_ref )) || fail '--message may be specified once'
        # shellcheck disable=SC2034 # This nameref returns the message to main.
        message_ref=$2
        message_seen_ref=1
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

  (( message_seen_ref )) || {
    usage
    fail 'The --message option is required.'
  }
}

main() {
  local message=''
  # shellcheck disable=SC2034 # Passed by nameref to parse_arguments.
  local message_seen=0
  local familiar_name=''
  local pane_id=''

  parse_arguments message message_seen "$@"
  readonly message
  [[ -n ${TMUX:-} ]] || fail 'This message command must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This message command must run from a tmux pane.'
  familiar_resolve_live_familiar familiar_name pane_id "$TMUX_PANE" || exit 1
  readonly familiar_name pane_id

  if ! tmux send-keys -t "$pane_id" -l -- "$message"; then
    fail "Could not deliver the message to Familiar $familiar_name in pane $pane_id."
  fi
  sleep "$MESSAGE_SUBMISSION_DELAY_SECONDS"
  if ! tmux send-keys -t "$pane_id" C-m; then
    fail "Message text was delivered to Familiar $familiar_name in pane $pane_id, but Enter failed; the message may remain unsubmitted."
  fi
  printf 'Sent message to Familiar %s in pane %s.\n' "$familiar_name" "$pane_id"
}

main "$@"
