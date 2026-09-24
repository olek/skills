#!/usr/bin/env bash
# Shared Familiar storage, naming, and path derivation.
#
# This is the source of truth for the Familiar home, the antechamber, the
# YYMMDD-HHMM naming convention, bare-name validation, and request/response/
# session path derivation. Source it from the other Familiar scripts, or run it
# directly so a summoning agent can ask for a path before summoning a Familiar.
# The --request-path query also creates the antechamber directory, so the agent
# can write the returned path without preparing any directory itself.

familiar_storage_directory() {
  local directory=${FAMILIAR_HOME:-}

  if [[ -z $directory ]]; then
    [[ -n ${HOME:-} ]] || return 1
    directory="$HOME/.familiar"
  fi

  printf '%s\n' "$directory"
}

familiar_validate_storage_directory() {
  [[ $1 = /* ]]
}

familiar_antechamber_directory() {
  local directory

  directory=$(familiar_storage_directory) || return 1
  readonly directory
  familiar_validate_storage_directory "$directory" || return 1
  printf '%s/antechamber\n' "${directory%/}"
}

familiar_summonings_directory() {
  local directory

  directory=$(familiar_storage_directory) || return 1
  readonly directory
  familiar_validate_storage_directory "$directory" || return 1
  printf '%s/summonings\n' "${directory%/}"
}

familiar_configuration_directory() {
  local directory

  directory=$(familiar_storage_directory) || return 1
  readonly directory
  familiar_validate_storage_directory "$directory" || return 1
  printf '%s/config\n' "${directory%/}"
}

familiar_intent_overrides_path() {
  local configuration_directory

  configuration_directory=$(familiar_configuration_directory) || return 1
  readonly configuration_directory
  printf '%s/intent-overrides.conf\n' "$configuration_directory"
}

familiar_ensure_home_layout() {
  local storage_directory
  local antechamber_directory
  local configuration_directory
  local summonings_directory

  storage_directory=$(familiar_storage_directory) || return 1
  readonly storage_directory
  familiar_validate_storage_directory "$storage_directory" || return 1
  antechamber_directory=$(familiar_antechamber_directory) || return 1
  configuration_directory=$(familiar_configuration_directory) || return 1
  summonings_directory=$(familiar_summonings_directory) || return 1
  readonly antechamber_directory configuration_directory summonings_directory
  mkdir -p -- "$antechamber_directory" "$configuration_directory" "$summonings_directory"
}

familiar_current_timestamp() {
  date +%y%m%d-%H%M
}

familiar_validate_timestamp() {
  [[ $1 =~ ^[0-9]{6}-[0-9]{4}$ ]]
}

familiar_validate_name() {
  local -r familiar_name=$1

  [[ $familiar_name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || return 1
  [[ ! $familiar_name =~ ^(fm|rq|rs)(-|$) ]]
}

familiar_session_name() {
  local -r familiar_timestamp=$1
  local -r familiar_name=$2

  printf '%s-fm-%s\n' "$familiar_timestamp" "$familiar_name"
}

familiar_request_filename() {
  local -r familiar_timestamp=$1
  local -r familiar_name=$2

  printf '%s-rq-%s.md\n' "$familiar_timestamp" "$familiar_name"
}

familiar_response_filename() {
  local -r familiar_timestamp=$1
  local -r familiar_name=$2

  printf '%s-rs-%s.md\n' "$familiar_timestamp" "$familiar_name"
}

familiar_staged_request_filename() {
  local -r familiar_name=$1

  printf '%s.md\n' "$familiar_name"
}

familiar_path_in_storage() {
  local -r filename=$1
  local summonings_directory

  summonings_directory=$(familiar_summonings_directory) || return 1
  readonly summonings_directory
  familiar_path_in_directory "$summonings_directory" "$filename"
}

familiar_path_in_directory() {
  local -r directory=$1
  local -r filename=$2

  familiar_validate_storage_directory "$directory" || return 1
  printf '%s/%s\n' "${directory%/}" "$filename"
}

familiar_request_path() {
  familiar_path_in_storage "$(familiar_request_filename "$1" "$2")"
}

familiar_staged_request_path() {
  local antechamber_directory

  antechamber_directory=$(familiar_antechamber_directory) || return 1
  readonly antechamber_directory
  printf '%s/%s\n' "$antechamber_directory" "$(familiar_staged_request_filename "$1")"
}

familiar_response_path() {
  familiar_path_in_storage "$(familiar_response_filename "$1" "$2")"
}

familiar_paths_usage() {
  printf '%s\n' \
    "Usage: ${0##*/} --directory" \
    "       ${0##*/} --antechamber-directory" \
    "       ${0##*/} --summonings-directory" \
    "       ${0##*/} --intent-overrides-path" \
    "       ${0##*/} --session-name --name <bare-familiar-name>" \
    "       ${0##*/} --request-path --name <bare-familiar-name>" \
    "       ${0##*/} --response-path --name <bare-familiar-name>" >&2
}

familiar_paths_fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

familiar_paths_main() {
  set -euo pipefail

  local output_kind=''
  local familiar_name=''

  while (($#)); do
    case "$1" in
      --directory|--antechamber-directory|--summonings-directory|--intent-overrides-path|--session-name|--request-path|--response-path)
        [[ -z $output_kind ]] || familiar_paths_fail 'Choose one output option.'
        output_kind=$1
        shift
        ;;
      --name)
        (($# >= 2)) || familiar_paths_fail 'Missing value for --name'
        [[ -z $familiar_name ]] || familiar_paths_fail '--name may be specified once'
        familiar_name=$2
        shift 2
        ;;
      --help)
        familiar_paths_usage
        exit 0
        ;;
      *)
        familiar_paths_usage
        familiar_paths_fail "Unknown option: $1"
        ;;
    esac
  done

  readonly output_kind familiar_name
  [[ -n $output_kind ]] || {
    familiar_paths_usage
    familiar_paths_fail 'An output option is required.'
  }

  local storage_directory
  storage_directory=$(familiar_storage_directory) || familiar_paths_fail 'HOME must be set when FAMILIAR_HOME is not set.'
  readonly storage_directory
  familiar_validate_storage_directory "$storage_directory" || familiar_paths_fail 'FAMILIAR_HOME must be an absolute path.'

  if [[ $output_kind == '--directory' || $output_kind == '--antechamber-directory' || $output_kind == '--summonings-directory' || $output_kind == '--intent-overrides-path' ]]; then
    [[ -z $familiar_name ]] || familiar_paths_fail '--name is not used with directory output options'
    case "$output_kind" in
      --directory)
        printf '%s\n' "$storage_directory"
        ;;
      --antechamber-directory)
        familiar_antechamber_directory
        ;;
      --summonings-directory)
        familiar_summonings_directory
        ;;
      --intent-overrides-path)
        familiar_intent_overrides_path
        ;;
    esac
    return
  fi

  [[ -n $familiar_name ]] || familiar_paths_fail "${output_kind} requires --name <bare-familiar-name>"
  familiar_validate_name "$familiar_name" || familiar_paths_fail 'Familiar name must be lowercase kebab-case without an fm, rq, or rs prefix.'

  local familiar_timestamp
  familiar_timestamp=$(familiar_current_timestamp)
  readonly familiar_timestamp
  case "$output_kind" in
    --session-name)
      familiar_session_name "$familiar_timestamp" "$familiar_name"
      ;;
    --request-path)
      familiar_ensure_home_layout || familiar_paths_fail 'Could not create the Familiar home layout.'
      familiar_staged_request_path "$familiar_name"
      ;;
    --response-path)
      familiar_response_path "$familiar_timestamp" "$familiar_name"
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  familiar_paths_main "$@"
fi
