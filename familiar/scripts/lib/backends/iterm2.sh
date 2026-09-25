#!/usr/bin/env bash
# Bridge the terminal contract to a one-shot iTerm2 Python API connection.

FAMILIAR_ITERM2_BRIDGE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/iterm2-bridge.py
readonly FAMILIAR_ITERM2_BRIDGE

familiar_iterm2_call() {
  "${FAMILIAR_ITERM2_PYTHON:-python3}" "$FAMILIAR_ITERM2_BRIDGE" "$@"
}

familiar_backend_require_context() {
  [[ -z ${TMUX:-} ]] || { printf 'iTerm2 backend cannot run inside tmux.\n' >&2; return 1; }
  [[ ${BASH_VERSINFO[0]} -gt 4 || ( ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -ge 3 ) ]] || { printf 'iTerm2 backend requires Bash 4.3 or newer.\n' >&2; return 1; }
  [[ ${ITERM_SESSION_ID:-} =~ ^[^:]+:([^:]+)$ ]] || { printf 'iTerm2 backend requires a valid ITERM_SESSION_ID.\n' >&2; return 1; }
  command -v realpath >/dev/null && [[ $(realpath --version 2>/dev/null | head -1) == *'GNU coreutils'* ]] || { printf 'iTerm2 backend requires GNU coreutils realpath on PATH.\n' >&2; return 1; }
  command -v mv >/dev/null && [[ $(mv --version 2>/dev/null | head -1) == *'GNU coreutils'* ]] || { printf 'iTerm2 backend requires GNU coreutils mv on PATH.\n' >&2; return 1; }
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
  local -r origin=$1 cwd=$2 command=$3 name=$4 timestamp=$5 harness=$6 home=$7
  printf '%s' "$command" | familiar_iterm2_call launch "$origin" "$cwd" "$name" "$timestamp" "$harness" "$home"
}

familiar_backend_send_literal() {
  printf '%s' "$2" | familiar_iterm2_call send "${ITERM_SESSION_ID#*:}" "$1"
}

familiar_backend_submit() {
  familiar_iterm2_call submit "${ITERM_SESSION_ID#*:}" "$1"
}

familiar_backend_close_familiar() {
  familiar_iterm2_call close "${ITERM_SESSION_ID#*:}" "$1"
}

familiar_backend_display_noun() { printf 'session'; }
