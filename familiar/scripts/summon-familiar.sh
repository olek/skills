#!/usr/bin/env bash
# Summon one managed Familiar beside its requesting pane.
#
# This is the tmux-backed counterpart to headless delegation: it starts a
# named, inspectable Familiar in a pane, promotes its staged request from the
# antechamber to durable timestamped storage, and records the metadata needed
# to reconstruct its request and response paths.  The Familiar's harness is
# explicit and independent of the summoning agent. One managed Familiar is
# allowed per summoning agent instance.
#
# Run this only from the pane that requested the Familiar, with a bare
# --name, an absolute --cwd path, a required --harness, and optional
# model/effort settings.
# TMUX_PANE is intentionally used as the target rather than tmux's active
# client/window.  Consequently, if the user switches windows or sessions while
# the Familiar is being prepared, it still opens in the requesting pane's
# window.
set -euo pipefail

readonly PROGRAM_NAME="${0##*/}"
SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY
readonly FAMILIAR_OPTION='@familiar'
readonly FAMILIAR_NAME_OPTION='@familiar_name'
readonly FAMILIAR_TIMESTAMP_OPTION='@familiar_timestamp'
readonly FAMILIAR_HARNESS_OPTION='@familiar_harness'
readonly FAMILIAR_HOME_OPTION='@familiar_home'
readonly FAMILIAR_SUMMONER_PANE_OPTION='@familiar_summoner_pane'
readonly FAMILIAR_STATUS_LINE_CONFIG='tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]'

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/familiar-paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/familiar-harness.sh"

usage() {
  printf 'Usage: %s --name <bare-familiar-name> --cwd <absolute-project-directory> --harness <harness> [--model <target-harness-model>] [--effort <target-harness-effort>]\n' "$PROGRAM_NAME" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

parse_arguments() {
  local -n familiar_name_ref=$1
  local -n working_directory_ref=$2
  local -n harness_ref=$3
  local -n model_ref=$4
  local -n effort_ref=$5
  shift 5

  while (($#)); do
    case "$1" in
      --name|--cwd|--harness|--model|--effort)
        (($# >= 2)) || fail "Missing value for $1"
        case "$1" in
          --name)
            [[ -z $familiar_name_ref ]] || fail '--name may be specified once'
            familiar_name_ref=$2
            ;;
          --cwd)
            [[ -z $working_directory_ref ]] || fail '--cwd may be specified once'
            working_directory_ref=$2
            ;;
          --harness)
            [[ -z $harness_ref ]] || fail '--harness may be specified once'
            [[ -n $2 ]] || fail '--harness requires one non-empty value'
            # shellcheck disable=SC2034 # This nameref returns the harness to main.
            harness_ref=$2
            ;;
          --model)
            [[ -z $model_ref && -n $2 ]] || fail '--model requires one non-empty value'
            model_ref=$2
            ;;
          --effort)
            [[ -z $effort_ref && -n $2 ]] || fail '--effort requires one non-empty value'
            effort_ref=$2
            ;;
        esac
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

validate_inputs() {
  local -r familiar_name=$1
  local -r working_directory=$2
  local -r harness=$3
  local -r model=$4
  local -r effort=$5

  [[ -n ${TMUX:-} ]] || fail 'This launcher must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This launcher must run from a tmux pane.'
  [[ -n $familiar_name && -n $working_directory && -n $harness ]] || {
    usage
    fail 'The --name, --cwd, and --harness options are required.'
  }
  familiar_validate_name "$familiar_name" || fail 'Familiar name must be lowercase kebab-case without an fm, fmrq, or fmrs prefix.'
  [[ $working_directory = /* ]] || fail 'The --cwd path must be absolute.'
  familiar_harness_load "$harness" || return 1
  local executable
  executable=$(familiar_harness_executable) || fail "Harness does not define an executable: $harness"
  readonly executable
  command -v "$executable" >/dev/null 2>&1 || fail "The $executable executable is not available: $executable"
  [[ -z $model || $model != -* ]] || fail 'Model ID must not begin with a hyphen.'
  [[ -z $effort || $effort != -* ]] || fail 'Reasoning effort must not begin with a hyphen.'
  [[ $model != default ]] || fail 'Omit --model to use the harness-configured default.'
  [[ $effort != default ]] || fail 'Omit --effort to use the harness-configured default.'
}

resolve_paths() {
  local -n resolved_staged_request_file_ref=$1
  local -n resolved_request_file_ref=$2
  local -n resolved_response_file_ref=$3
  local -n resolved_working_directory_ref=$4
  local -n resolved_storage_directory_ref=$5
  local -r familiar_timestamp=$6
  local -r familiar_name=$7
  local -r working_directory_input=$8
  local antechamber_directory
  local storage_directory_input
  local staged_request_file_input
  local request_file_input
  local response_file_input
  local storage_parent
  local request_basename
  local response_basename

  storage_directory_input=$(familiar_storage_directory) || fail 'HOME must be set when FAMILIAR_HOME is not set.'
  familiar_validate_storage_directory "$storage_directory_input" || fail 'FAMILIAR_HOME must be an absolute path.'
  antechamber_directory=$(familiar_antechamber_directory)
  staged_request_file_input=$(familiar_staged_request_path "$familiar_name")
  request_file_input=$(familiar_request_path "$familiar_timestamp" "$familiar_name")
  response_file_input=$(familiar_response_path "$familiar_timestamp" "$familiar_name")
  readonly antechamber_directory storage_directory_input staged_request_file_input request_file_input response_file_input

  [[ -f $staged_request_file_input && -r $staged_request_file_input ]] || fail "Staged request is not a readable file: $staged_request_file_input"
  [[ -d $storage_directory_input && -r $storage_directory_input && -w $storage_directory_input ]] || fail "Familiar storage directory is not a writable directory: $storage_directory_input"
  [[ -d $antechamber_directory && -r $antechamber_directory && -w $antechamber_directory ]] || fail "Familiar antechamber is not a writable directory: $antechamber_directory"
  [[ ! -e $request_file_input ]] || fail "Request path already exists: $request_file_input"
  [[ ! -e $response_file_input ]] || fail "Response path already exists: $response_file_input"
  [[ -d $working_directory_input && -r $working_directory_input ]] || fail "Working directory is not readable: $working_directory_input"

  storage_parent=$(realpath -e -- "$storage_directory_input") || fail "Familiar storage directory does not exist: $storage_directory_input"
  readonly storage_parent
  # shellcheck disable=SC2034 # This nameref returns canonical Familiar home to main.
  resolved_storage_directory_ref=$storage_parent
  request_basename=${request_file_input##*/}
  response_basename=${response_file_input##*/}
  readonly request_basename response_basename
  # shellcheck disable=SC2034 # These namerefs return resolved paths to main.
  resolved_staged_request_file_ref=$(realpath -e -- "$staged_request_file_input")
  # shellcheck disable=SC2034 # These namerefs return resolved paths to main.
  resolved_working_directory_ref=$(realpath -e -- "$working_directory_input")
  if [[ $storage_parent == / ]]; then
    resolved_request_file_ref="/$request_basename"
    resolved_response_file_ref="/$response_basename"
  else
    # shellcheck disable=SC2034 # This nameref returns the resolved request path to main.
    resolved_request_file_ref="$storage_parent/$request_basename"
    # shellcheck disable=SC2034 # This nameref returns the resolved response path to main.
    resolved_response_file_ref="$storage_parent/$response_basename"
  fi
}

ensure_no_managed_familiar() {
  if tmux list-panes -a -F $'#{@familiar}\t#{@familiar_summoner_pane}' \
    | awk -F '\t' -v summoner="$TMUX_PANE" '$1 == "1" && $2 == summoner { found = 1 } END { exit found ? 0 : 1 }'; then
    fail 'This summoning agent instance already has a managed Familiar; close it before summoning another.'
  fi
}

build_familiar_prompt() {
  local -r request_file=$1
  local -r response_file=$2

  printf 'Read and follow the request at %s. The resolved response path is %s. Work only within its stated scope. Do not create %s until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents (cheaper models are fine), but make every file change yourself.' \
    "$request_file" "$response_file" "$response_file"
}

launch_familiar() {
  local -r working_directory=$1
  local -r pane_command=$2
  local -r familiar_name=$3
  local -r familiar_timestamp=$4
  local -r harness=$5
  local -r storage_directory=$6
  local window_id
  local pane_id

  window_id=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
  readonly window_id
  if ! pane_id=$(tmux split-window -h -c "$working_directory" -t "$window_id" -P -F '#{pane_id}' "$pane_command"); then
    return 1
  fi
  readonly pane_id
  if ! tmux set-option -p -t "$pane_id" "$FAMILIAR_NAME_OPTION" "$familiar_name" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TIMESTAMP_OPTION" "$familiar_timestamp" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_HARNESS_OPTION" "$harness" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_HOME_OPTION" "$storage_directory" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_SUMMONER_PANE_OPTION" "$TMUX_PANE" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_OPTION" 1; then
    tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    return 1
  fi
  printf '%s\n' "$pane_id"
}

main() {
  local familiar_name_input=''
  local working_directory_input=''
  local harness=''
  local model=''
  local effort=''
  local familiar_timestamp
  local session_name
  local staged_request_file
  local request_file
  local response_file
  local working_directory
  local storage_directory
  local familiar_prompt
  local pane_command

  parse_arguments familiar_name_input working_directory_input harness model effort "$@"
  readonly familiar_name_input working_directory_input harness model effort
  validate_inputs "$familiar_name_input" "$working_directory_input" "$harness" "$model" "$effort"
  familiar_timestamp=$(familiar_current_timestamp)
  readonly familiar_timestamp
  session_name=$(familiar_session_name "$familiar_timestamp" "$familiar_name_input")
  readonly session_name
  resolve_paths staged_request_file request_file response_file working_directory storage_directory "$familiar_timestamp" "$familiar_name_input" "$working_directory_input"
  readonly staged_request_file request_file response_file working_directory storage_directory
  ensure_no_managed_familiar

  familiar_prompt=$(build_familiar_prompt "$request_file" "$response_file")
  readonly familiar_prompt
  pane_command=$(familiar_harness_build_command "$working_directory" "$session_name" "$familiar_prompt" "$model" "$effort" "$FAMILIAR_STATUS_LINE_CONFIG")
  readonly pane_command

  # Promotion is the durable handoff boundary. Restore the staged request if
  # pane creation or metadata setup fails so the caller can safely retry.
  mv --no-clobber -- "$staged_request_file" "$request_file" || fail "Could not promote staged request: $staged_request_file"
  [[ ! -e $staged_request_file ]] || fail "Request path already exists; staged request was preserved: $request_file"
  local pane_id
  if ! pane_id=$(launch_familiar "$working_directory" "$pane_command" "$familiar_name_input" "$familiar_timestamp" "$harness" "$storage_directory"); then
    if [[ ! -e $staged_request_file ]] && mv --no-clobber -- "$request_file" "$staged_request_file"; then
      fail "Could not launch the Familiar; restored the staged request: $staged_request_file"
    fi
    fail "Could not launch the Familiar; recover the request from: $request_file"
  fi
  readonly pane_id
  printf '%s\n' "$pane_id"
  printf 'request: %s\nresponse: %s\n' "$request_file" "$response_file"
}

main "$@"
