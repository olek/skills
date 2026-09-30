#!/usr/bin/env bash
# Bridge the terminal contract to a one-shot iTerm2 Python API connection.

FAMILIAR_ITERM2_BRIDGE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/iterm2-bridge.py
readonly FAMILIAR_ITERM2_BRIDGE
# shellcheck disable=SC1091
source "${FAMILIAR_ITERM2_BRIDGE%/*}/../../paths.sh"

familiar_iterm2_resolve_gnu_tool() {
  local tool=$1 candidate path
  for candidate in "$tool" "g$tool"; do
    path=$(type -P "$candidate") || continue
    [[ -x $path ]] || continue
    [[ $("$path" --version 2>/dev/null | head -1) == *'GNU coreutils'* ]] || continue
    printf '%s\n' "$path"
    return 0
  done
  return 1
}

familiar_iterm2_version_is_newer() {
  local left=$1 right=$2 index left_part right_part
  local -a left_parts=() right_parts=()
  IFS=. read -r -a left_parts <<< "$left"
  IFS=. read -r -a right_parts <<< "$right"
  for ((index = 0; index < ${#left_parts[@]} || index < ${#right_parts[@]}; index++)); do
    left_part=${left_parts[index]:-0}
    right_part=${right_parts[index]:-0}
    [[ $left_part =~ ^[0-9]+$ ]] || left_part=0
    [[ $right_part =~ ^[0-9]+$ ]] || right_part=0
    (( 10#$left_part > 10#$right_part )) && return 0
    (( 10#$left_part < 10#$right_part )) && return 1
  done
  return 1
}

familiar_iterm2_python() {
  if [[ -n ${FAMILIAR_ITERM2_PYTHON:-} ]]; then
    printf '%s\n' "$FAMILIAR_ITERM2_PYTHON"
    return 0
  fi

  local default_python candidate best='' candidate_version best_version=''
  default_python=$(type -P python3) || default_python=''
  if [[ -n $default_python ]] && "$default_python" -c 'import importlib.util, sys; sys.exit(importlib.util.find_spec("iterm2") is None)' >/dev/null 2>&1; then
    printf '%s\n' "$default_python"
    return 0
  fi

  local runtime_root="${HOME:-}/Library/ApplicationSupport/iTerm2/iterm2env/versions"
  for candidate in "$runtime_root"/*/bin/python3; do
    [[ -x $candidate ]] || continue
    "$candidate" -c 'import importlib.util, sys; sys.exit(importlib.util.find_spec("iterm2") is None)' >/dev/null 2>&1 || continue
    candidate_version=${candidate#"$runtime_root"/}
    candidate_version=${candidate_version%%/*}
    if [[ -z $best ]] || familiar_iterm2_version_is_newer "$candidate_version" "$best_version"; then
      best=$candidate
      best_version=$candidate_version
    fi
  done
  if [[ -n $best ]]; then
    printf '%s\n' "$best"
    return 0
  fi
  if [[ -n $default_python ]]; then
    printf '%s\n' "$default_python"
    return 0
  fi
  printf 'iTerm2 Python package unavailable; set FAMILIAR_ITERM2_PYTHON to a Python 3 executable with iterm2 installed.\n' >&2
  return 1
}

familiar_iterm2_call() {
  local home python realpath
  home=$(familiar_home) || return 1
  python=$(familiar_iterm2_python) || return 1
  realpath=${FAMILIAR_BACKEND_REALPATH:-}
  if [[ -z $realpath ]]; then
    realpath=$(familiar_iterm2_resolve_gnu_tool realpath) || { printf 'iTerm2 backend requires GNU realpath or grealpath on PATH.\n' >&2; return 1; }
  fi
  FAMILIAR_CANONICAL_HOME=$("$realpath" -m -- "$home") \
    "$python" "$FAMILIAR_ITERM2_BRIDGE" "$@"
}

familiar_backend_require_context() {
  [[ -z ${TMUX:-} ]] || { printf 'iTerm2 backend cannot run inside tmux.\n' >&2; return 1; }
  [[ ${FAMILIAR_BACKEND:-auto} == iterm2 || ${TERM_PROGRAM:-} == iTerm.app ]] || { printf 'iTerm2 backend requires TERM_PROGRAM=iTerm.app unless FAMILIAR_BACKEND=iterm2 is explicit.\n' >&2; return 1; }
  [[ ${ITERM_SESSION_ID:-} =~ ^[^:]+:([^:]+)$ ]] || { printf 'iTerm2 backend requires a valid ITERM_SESSION_ID.\n' >&2; return 1; }
  FAMILIAR_BACKEND_REALPATH=$(familiar_iterm2_resolve_gnu_tool realpath) || { printf 'iTerm2 backend requires GNU realpath or grealpath on PATH.\n' >&2; return 1; }
  FAMILIAR_BACKEND_MV=$(familiar_iterm2_resolve_gnu_tool mv) || { printf 'iTerm2 backend requires GNU mv or gmv on PATH.\n' >&2; return 1; }
  familiar_iterm2_call check "${BASH_REMATCH[1]}"
}

familiar_backend_summoner_id() {
  printf '%s\n' "${ITERM_SESSION_ID#*:}"
}

familiar_backend_list_familiars() {
  familiar_iterm2_call list "$1"
}

familiar_backend_can_launch() {
  familiar_iterm2_call can-launch "$1"
}

familiar_backend_launch_familiar() {
  local -r summoner_id=$1 cwd=$2 command=$3 name=$4 timestamp=$5 harness=$6 home=$7
  local launcher output status
  launcher=$(mktemp /tmp/familiar-launch.XXXXXX) || { printf 'Could not create the iTerm2 launch script.\n' >&2; return 1; }
  if ! {
    printf '#!/bin/sh\nrm -f -- "$0"\n"${SHELL:-/bin/zsh}" -l -i -c %s familiar-launch %s %s\nstatus=$?\nif [ "$status" -ne 0 ]; then\n  stty sane 2>/dev/null\n  printf '\''\\033]1337;SetUserVar=familiar_exit=%%s\\007'\'' "$(printf %%s "$status" | base64)"\n  printf '\''Familiar command failed (status %%s); press Enter to close.\\n'\'' "$status"\n  IFS= read -r _\nfi\nexit "$status"\n' \
      "$(shell_quote 'PATH=$1; export PATH; eval "$2"')" \
      "$(shell_quote "$PATH")" "$(shell_quote "$command")"
  } > "$launcher" || ! chmod 700 "$launcher"; then
    rm -f "$launcher"
    printf 'Could not prepare the iTerm2 launch script.\n' >&2
    return 1
  fi
  if output=$(familiar_iterm2_call launch "$summoner_id" "$cwd" "$name" "$timestamp" "$harness" "$home" "$launcher"); then
    printf '%s\n' "$output"
  else
    status=$?
    rm -f "$launcher"
    return "$status"
  fi
}

familiar_backend_send_literal() {
  printf '%s' "$2" | familiar_iterm2_call send "$(familiar_backend_summoner_id)" "$1"
}

familiar_backend_submit() {
  familiar_iterm2_call submit "$(familiar_backend_summoner_id)" "$1"
}

familiar_backend_close_familiar() {
  familiar_iterm2_call close "$(familiar_backend_summoner_id)" "$1"
}

familiar_backend_display_noun() { printf 'session'; }
