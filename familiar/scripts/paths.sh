#!/usr/bin/env bash
# Shared Familiar home, validation, and path derivation.

if [[ ${BASH_VERSINFO[0]} -lt 4 || ( ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 3 ) ]]; then
  printf 'Familiar requires Bash 4.3 or newer (found %s); install bash and put it first on PATH.\n' "$BASH_VERSION" >&2
  exit 1
fi

familiar_home() {
  local home=${FAMILIAR_HOME:-}
  if [[ -z $home ]]; then
    [[ -n ${HOME:-} ]] || { printf 'HOME must be set when FAMILIAR_HOME is not set.\n' >&2; return 1; }
    home="$HOME/.familiar"
  fi
  familiar_validate_home "$home" || { printf 'FAMILIAR_HOME must be an absolute path.\n' >&2; return 1; }
  home=${home%/}
  [[ -n $home ]] || { printf 'FAMILIAR_HOME must be an absolute path.\n' >&2; return 1; }
  printf '%s\n' "$home"
}

familiar_validate_home() { [[ $1 = /* ]]; }

familiar_intent_config_path() {
  local home
  home=$(familiar_home) || return 1
  printf '%s/config/intent.conf\n' "$home"
}

familiar_ensure_home_layout() {
  local -r home=$1
  mkdir -p -- "$home/antechamber" "$home/config" "$home/summonings"
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

familiar_summoning_paths() {
  local -r home=$1 timestamp=$2 name=$3
  familiar_validate_home "$home" || return 1
  familiar_validate_timestamp "$timestamp" || return 1
  familiar_validate_name "$name" || return 1
  printf '%s\t%s\t%s\n' \
    "$home/antechamber/$(familiar_staged_request_filename "$name")" \
    "$home/summonings/$(familiar_request_filename "$timestamp" "$name")" \
    "$home/summonings/$(familiar_response_filename "$timestamp" "$name")"
}

familiar_paths_usage() {
  printf 'Usage: %s --request-path --name <bare-familiar-name>\n' "${0##*/}" >&2
}

familiar_paths_fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

familiar_paths_main() {
  set -euo pipefail
  local output_seen=0 name=''
  while (($#)); do
    case "$1" in
      --request-path)
        (( ! output_seen )) || familiar_paths_fail 'Choose one output option.'
        output_seen=1
        shift ;;
      --name)
        (($# >= 2)) || familiar_paths_fail 'Missing value for --name'
        [[ -z $name ]] || familiar_paths_fail '--name may be specified once'
        name=$2
        shift 2 ;;
      --help)
        familiar_paths_usage
        exit 0 ;;
      *)
        familiar_paths_usage
        familiar_paths_fail "Unknown option: $1" ;;
    esac
  done
  (( output_seen )) || familiar_paths_fail 'An output option is required.'
  [[ -n $name ]] || familiar_paths_fail '--request-path requires --name <bare-familiar-name>'
  familiar_validate_name "$name" || familiar_paths_fail 'Familiar name must be lowercase kebab-case without an fm, rq, or rs prefix.'
  local home
  home=$(familiar_home) || exit 1
  familiar_ensure_home_layout "$home" || familiar_paths_fail 'Could not create the Familiar home layout.'
  printf '%s/antechamber/%s\n' "$home" "$(familiar_staged_request_filename "$name")"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  familiar_paths_main "$@"
fi
