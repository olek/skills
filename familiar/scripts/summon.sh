#!/usr/bin/env bash
# Summon one managed Familiar in a visible terminal.
# Promote its staged request and retain paths for status reporting.
set -euo pipefail

readonly PROGRAM_NAME="${0##*/}"
SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/paths.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/harness.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIRECTORY/lib/backend.sh"

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

  familiar_backend_require_context || exit 1
  [[ -n $familiar_name && -n $working_directory && -n $harness ]] || {
    usage
    fail 'The --name, --cwd, and --harness options are required.'
  }
  familiar_validate_name "$familiar_name" || fail 'Familiar name must be lowercase kebab-case without an fm, rq, or rs prefix.'
  [[ $working_directory = /* ]] || fail 'The --cwd path must be absolute.'
  familiar_harness_load "$harness" || return 1
  local executable
  executable=$(familiar_harness_executable) || fail "Harness does not define an executable: $harness"
  readonly executable
  command -v "$executable" >/dev/null 2>&1 || fail "The executable is not available: $executable"
  [[ -z $model || $model != -* ]] || fail 'Model ID must not begin with a hyphen.'
  [[ -z $effort || $effort != -* ]] || fail 'Reasoning effort must not begin with a hyphen.'
  [[ $model != default ]] || fail 'Omit --model to use the harness-configured default.'
  [[ $effort != default ]] || fail 'Omit --effort to use the harness-configured default.'
}

resolve_paths() {
  local -n staged_ref=$1 request_ref=$2 response_ref=$3 cwd_ref=$4 home_ref=$5
  local -r timestamp=$6 name=$7 cwd_input=$8
  local home_input paths staged request response summonings

  home_input=$(familiar_home) || exit 1
  familiar_ensure_home_layout "$home_input" || fail 'Could not create the Familiar home layout.'
  paths=$(familiar_summoning_paths "$home_input" "$timestamp" "$name")
  IFS=$'\t' read -r staged request response <<< "$paths"
  summonings="$home_input/summonings"

  [[ -f $staged && -r $staged ]] || fail "Staged request is not a readable file: $staged"
  [[ -d $home_input && -r $home_input && -w $home_input ]] || fail "Familiar storage directory is not a writable directory: $home_input"
  [[ -d $home_input/antechamber && -r $home_input/antechamber && -w $home_input/antechamber ]] || fail "Familiar antechamber is not a writable directory: $home_input/antechamber"
  [[ -d $summonings && -r $summonings && -w $summonings ]] || fail "Familiar summonings directory is not a writable directory: $summonings"
  [[ ! -e $request ]] || fail "Request path already exists: $request"
  [[ ! -e $response ]] || fail "Response path already exists: $response"
  [[ -d $cwd_input && -r $cwd_input ]] || fail "Working directory is not readable: $cwd_input"

  # shellcheck disable=SC2034 # Nameref returns the value to main.
  home_ref=$(realpath -e -- "$home_input")
  # shellcheck disable=SC2034 # Nameref returns the value to main.
  staged_ref=$(realpath -e -- "$staged")
  # shellcheck disable=SC2034 # Nameref returns the value to main.
  cwd_ref=$(realpath -e -- "$cwd_input")
  # shellcheck disable=SC2034 # Nameref returns the value to main.
  request_ref="$home_ref/summonings/${request##*/}"
  # shellcheck disable=SC2034 # Nameref returns the value to main.
  response_ref="$home_ref/summonings/${response##*/}"
}

ensure_no_managed_familiar() {
  local -r summoner_id=$1

  familiar_backend_can_launch "$summoner_id" || exit 1
}

build_familiar_prompt() {
  local -r request_file=$1
  local -r response_file=$2

  printf 'Read and follow the request at %s. The resolved response path is %s. Work only within its stated scope. Do not create %s until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents as needed, but make every file change yourself. You are allowed to ask user clarifying questions as needed.' \
    "$request_file" "$response_file" "$response_file"
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
  local home
  local familiar_prompt
  local familiar_command
  local summoner_id

  parse_arguments familiar_name_input working_directory_input harness model effort "$@"
  readonly familiar_name_input working_directory_input harness model effort
  validate_inputs "$familiar_name_input" "$working_directory_input" "$harness" "$model" "$effort"
  summoner_id=$(familiar_backend_summoner_id)
  readonly summoner_id
  familiar_timestamp=$(familiar_current_timestamp)
  readonly familiar_timestamp
  session_name=$(familiar_session_name "$familiar_timestamp" "$familiar_name_input")
  readonly session_name
  resolve_paths staged_request_file request_file response_file working_directory home "$familiar_timestamp" "$familiar_name_input" "$working_directory_input"
  readonly staged_request_file request_file response_file working_directory home
  ensure_no_managed_familiar "$summoner_id"

  familiar_prompt=$(build_familiar_prompt "$request_file" "$response_file")
  readonly familiar_prompt
  familiar_command=$(familiar_harness_build_command "$working_directory" "$session_name" "$familiar_prompt" "$model" "$effort")
  readonly familiar_command

  # Promotion is the durable handoff boundary. Restore the staged request if
  # Familiar creation or metadata setup fails so the caller can safely retry.
  mv --no-clobber -- "$staged_request_file" "$request_file" || fail "Could not promote staged request: $staged_request_file"
  [[ ! -e $staged_request_file ]] || fail "Request path already exists; staged request was preserved: $request_file"
  local familiar_id
  if familiar_id=$(familiar_backend_launch_familiar "$summoner_id" "$working_directory" "$familiar_command" "$familiar_name_input" "$familiar_timestamp" "$harness" "$home"); then
    :
  else
    local launch_status=$?
    if (( launch_status == 3 )); then
      fail "Familiar terminal cleanup failed; preserve the promoted request and reconcile the terminal before retrying: $request_file"
    fi
    if [[ ! -e $staged_request_file ]] && mv --no-clobber -- "$request_file" "$staged_request_file"; then
      fail "Could not launch the Familiar; restored the staged request: $staged_request_file"
    fi
    fail "Could not launch the Familiar; recover the request from: $request_file"
  fi
  readonly familiar_id
  printf '%s\n' "$familiar_id"
  printf 'request: %s\nresponse: %s\n' "$request_file" "$response_file"
}

main "$@"
