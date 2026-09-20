#!/usr/bin/env bash
# Summon one managed Familiar beside its requesting pane.
#
# This is the tmux-backed counterpart to headless delegation: it starts a
# named, inspectable Familiar in a pane and records its request and response
# paths as pane options.  The Familiar's harness is explicit and independent of
# the orchestrator that requested it.  One managed Familiar is allowed per window.
#
# Run this only from the pane that requested the Familiar, with absolute --task,
# --response, and --cwd paths.  TMUX_PANE is intentionally used as the target
# rather than tmux's active client/window.  Consequently, if the user switches
# windows or sessions while the Familiar is being prepared, it still opens in the
# requesting pane's window.
set -euo pipefail

readonly PROGRAM_NAME="${0##*/}"
readonly FAMILIAR_OPTION='@familiar'
readonly FAMILIAR_NAME_OPTION='@familiar_name'
readonly FAMILIAR_HARNESS_OPTION='@familiar_harness'
readonly FAMILIAR_TASK_OPTION='@familiar_task'
readonly FAMILIAR_RESPONSE_OPTION='@familiar_response'
readonly FAMILIAR_STATUS_LINE_CONFIG='tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]'

usage() {
  printf 'Usage: %s --task <absolute-request-path> --response <absolute-response-path> --cwd <project-directory> [--harness <codex|claude>] [--model <target-harness-model>] [--effort <target-harness-effort>]\n' "$PROGRAM_NAME" >&2
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

shell_quote() {
  local escaped_value=$1
  escaped_value=${escaped_value//\'/\'"\'"\'}
  printf "'%s'" "$escaped_value"
}

parse_arguments() {
  local -n request_file_ref=$1
  local -n response_file_ref=$2
  local -n working_directory_ref=$3
  local -n harness_ref=$4
  local -n harness_seen_ref=$5
  local -n model_ref=$6
  local -n effort_ref=$7
  shift 7

  while (($#)); do
    case "$1" in
      --task|--response|--cwd|--harness|--model|--effort)
        (($# >= 2)) || fail "Missing value for $1"
        case "$1" in
          --task)
            [[ -z $request_file_ref ]] || fail '--task may be specified once'
            request_file_ref=$2
            ;;
          --response)
            [[ -z $response_file_ref ]] || fail '--response may be specified once'
            response_file_ref=$2
            ;;
          --cwd)
            [[ -z $working_directory_ref ]] || fail '--cwd may be specified once'
            working_directory_ref=$2
            ;;
          --harness)
            (( ! harness_seen_ref )) || fail '--harness may be specified once'
            [[ -n $2 ]] || fail '--harness requires one non-empty value'
            # shellcheck disable=SC2034 # This nameref returns the harness to main.
            harness_ref=$2
            harness_seen_ref=1
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
  local -r request_file=$1
  local -r response_file=$2
  local -r working_directory=$3
  local -r harness=$4
  local -r model=$5
  local -r effort=$6

  [[ -n ${TMUX:-} ]] || fail 'This launcher must run inside tmux.'
  [[ -n ${TMUX_PANE:-} ]] || fail 'This launcher must run from a tmux pane.'
  [[ -n $request_file && -n $response_file && -n $working_directory ]] || {
    usage
    fail 'The --task, --response, and --cwd options are required.'
  }
  [[ $request_file = /* && $response_file = /* && $working_directory = /* ]] || fail 'All supplied paths must be absolute.'
  case "$harness" in
    codex|claude)
      if ! command -v "$harness" >/dev/null 2>&1; then
        if [[ $harness == codex ]]; then
          fail 'The Codex executable is not available: codex'
        fi
        fail 'The Claude Code executable is not available: claude'
      fi
      ;;
    *)
      fail "Unknown harness: $harness (expected codex or claude)"
      ;;
  esac
  [[ -z $model || $model != -* ]] || fail 'Model ID must not begin with a hyphen.'
  [[ -z $effort || $effort != -* ]] || fail 'Reasoning effort must not begin with a hyphen.'
  if [[ $harness == claude && -n $effort ]]; then
    case "$effort" in
      low|medium|high|xhigh|max)
        ;;
      *)
        fail 'Claude effort must be one of: low, medium, high, xhigh, max.'
        ;;
    esac
  fi
}

resolve_paths() {
  local -n resolved_request_file_ref=$1
  local -n resolved_response_file_ref=$2
  local -n resolved_working_directory_ref=$3
  local -r request_file_input=$4
  local -r response_file_input=$5
  local -r working_directory_input=$6
  local response_parent_input=${response_file_input%/*}
  local response_parent
  local response_basename

  [[ -f $request_file_input && -r $request_file_input ]] || fail "Request is not a readable file: $request_file_input"
  [[ -d $working_directory_input && -r $working_directory_input ]] || fail "Working directory is not readable: $working_directory_input"
  [[ ! -e $response_file_input ]] || fail "Response path already exists: $response_file_input"

  [[ -n $response_parent_input ]] || response_parent_input='/'
  response_parent=$(realpath -e -- "$response_parent_input") || fail "Response parent does not exist: $response_parent_input"
  [[ -d $response_parent && -w $response_parent ]] || fail "Response parent is not writable: $response_parent"

  # shellcheck disable=SC2034 # These namerefs return resolved paths to main.
  resolved_request_file_ref=$(realpath -e -- "$request_file_input")
  # shellcheck disable=SC2034 # These namerefs return resolved paths to main.
  resolved_working_directory_ref=$(realpath -e -- "$working_directory_input")
  response_basename=${response_file_input##*/}
  if [[ $response_parent == / ]]; then
    resolved_response_file_ref="/$response_basename"
  else
    # shellcheck disable=SC2034 # This nameref returns the resolved response path to main.
    resolved_response_file_ref="$response_parent/$response_basename"
  fi
}

ensure_no_managed_familiar() {
  local window_id
  window_id=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
  readonly window_id

  local marker_format
  printf -v marker_format '#{%s}' "$FAMILIAR_OPTION"
  if tmux list-panes -t "$window_id" -F "$marker_format" \
    | awk '$1 == "1" { found = 1 } END { exit found ? 0 : 1 }'; then
    fail 'A managed Familiar already exists in this tmux window; close it before summoning another.'
  fi
}

build_familiar_prompt() {
  local -r request_file=$1
  local -r response_file=$2

  printf 'Read and follow the request at %s. Work only within its stated scope. Do not create %s until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents (cheaper models are fine), but make every file change yourself.' \
    "$request_file" "$response_file"
}

build_codex_command() {
  local -r working_directory=$1
  local -r familiar_prompt=$2
  local -r model=$3
  local -r effort=$4
  local command='exec codex --no-alt-screen --approve-for-me'

  printf -v command '%s --config %s' "$command" "$(shell_quote "$FAMILIAR_STATUS_LINE_CONFIG")"

  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  if [[ -n $effort ]]; then
    printf -v command '%s --config %s' "$command" "$(shell_quote "model_reasoning_effort=$effort")"
  fi
  printf -v command '%s --cd %s %s' "$command" \
    "$(shell_quote "$working_directory")" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}

build_claude_command() {
  local -r familiar_name=$1
  local -r familiar_prompt=$2
  local -r model=$3
  local -r effort=$4
  local command='CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1 exec claude --permission-mode auto'

  printf -v command '%s --name %s' "$command" "$(shell_quote "$familiar_name")"
  if [[ -n $model ]]; then
    printf -v command '%s --model %s' "$command" "$(shell_quote "$model")"
  fi
  if [[ -n $effort ]]; then
    printf -v command '%s --effort %s' "$command" "$(shell_quote "$effort")"
  fi
  printf -v command '%s %s' "$command" "$(shell_quote "$familiar_prompt")"
  printf '%s' "$command"
}

build_familiar_command() {
  local -r harness=$1
  local -r working_directory=$2
  local -r familiar_name=$3
  local -r familiar_prompt=$4
  local -r model=$5
  local -r effort=$6

  case "$harness" in
    codex)
      build_codex_command "$working_directory" "$familiar_prompt" "$model" "$effort"
      ;;
    claude)
      build_claude_command "$familiar_name" "$familiar_prompt" "$model" "$effort"
      ;;
    *)
      fail "Cannot build a launch command for harness: $harness"
      ;;
  esac
}

familiar_name_from_request() {
  local familiar_name=${1##*/}

  familiar_name=${familiar_name%.md}
  # Recover the session name (YYMMDD-fm-<slug>) from the request filename
  # (YYMMDD-fmrq-<slug>) by swapping the infix back.
  familiar_name=${familiar_name/-fmrq-/-fm-}
  # Claude's --name accepts only [A-Za-z0-9_-] (max 64); fold anything else out.
  familiar_name=${familiar_name//[^A-Za-z0-9_-]/-}
  printf '%s\n' "${familiar_name:0:64}"
}

launch_familiar() {
  local -r working_directory=$1
  local -r pane_command=$2
  local -r familiar_name=$3
  local -r harness=$4
  local -r request_file=$5
  local -r response_file=$6
  local window_id
  local pane_id

  window_id=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
  pane_id=$(tmux split-window -h -c "$working_directory" -t "$window_id" -P -F '#{pane_id}' "$pane_command")
  readonly pane_id
  tmux set-option -p -t "$pane_id" "$FAMILIAR_OPTION" 1
  tmux set-option -p -t "$pane_id" "$FAMILIAR_NAME_OPTION" "$familiar_name"
  tmux set-option -p -t "$pane_id" "$FAMILIAR_HARNESS_OPTION" "$harness"
  tmux set-option -p -t "$pane_id" "$FAMILIAR_TASK_OPTION" "$request_file"
  tmux set-option -p -t "$pane_id" "$FAMILIAR_RESPONSE_OPTION" "$response_file"
  printf '%s\n' "$pane_id"
}

main() {
  local request_file_input=''
  local response_file_input=''
  local working_directory_input=''
  local harness='codex'
  # shellcheck disable=SC2034 # Passed by nameref to parse_arguments.
  local harness_seen=0
  local model=''
  local effort=''
  local request_file
  local response_file
  local working_directory
  local familiar_prompt
  local familiar_name
  local pane_command

  parse_arguments request_file_input response_file_input working_directory_input harness harness_seen model effort "$@"
  readonly request_file_input response_file_input working_directory_input harness model effort
  validate_inputs "$request_file_input" "$response_file_input" "$working_directory_input" "$harness" "$model" "$effort"
  resolve_paths request_file response_file working_directory "$request_file_input" "$response_file_input" "$working_directory_input"
  readonly request_file response_file working_directory
  ensure_no_managed_familiar

  familiar_prompt=$(build_familiar_prompt "$request_file" "$response_file")
  readonly familiar_prompt
  familiar_name=$(familiar_name_from_request "$request_file")
  readonly familiar_name
  pane_command=$(build_familiar_command "$harness" "$working_directory" "$familiar_name" "$familiar_prompt" "$model" "$effort")
  readonly pane_command
  launch_familiar "$working_directory" "$pane_command" "$familiar_name" "$harness" "$request_file" "$response_file"
}

main "$@"
