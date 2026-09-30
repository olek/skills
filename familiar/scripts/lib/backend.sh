#!/usr/bin/env bash
# Load the terminal backend used by Familiar lifecycle commands.

if [[ ${BASH_VERSINFO[0]} -lt 4 || ( ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 3 ) ]]; then
  printf 'Familiar requires Bash 4.3 or newer (found %s); install bash and put it first on PATH.\n' "$BASH_VERSION" >&2
  exit 1
fi

FAMILIAR_BACKEND_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/backends" && pwd)
readonly FAMILIAR_BACKEND_DIRECTORY

case ${FAMILIAR_BACKEND:-auto} in
  auto)
    if [[ -n ${TMUX:-} ]]; then
      source "$FAMILIAR_BACKEND_DIRECTORY/tmux.sh"
    elif [[ -n ${ITERM_SESSION_ID:-} && ${TERM_PROGRAM:-} == iTerm.app ]]; then
      source "$FAMILIAR_BACKEND_DIRECTORY/iterm2.sh"
    else
      if [[ -n ${ITERM_SESSION_ID:-} ]]; then
        printf 'ITERM_SESSION_ID is set, but TERM_PROGRAM is not iTerm.app; refusing a possibly inherited iTerm2 session ID.\n' >&2
      fi
      printf 'No supported Familiar terminal backend is available; run inside tmux or a local iTerm2 session.\n' >&2
      return 1
    fi
    ;;
  tmux) source "$FAMILIAR_BACKEND_DIRECTORY/tmux.sh" ;;
  iterm2) source "$FAMILIAR_BACKEND_DIRECTORY/iterm2.sh" ;;
  *) printf 'Unknown Familiar backend: %s\n' "$FAMILIAR_BACKEND" >&2; return 1 ;;
esac

familiar_backend_realpath() {
  "${FAMILIAR_BACKEND_REALPATH:-realpath}" "$@"
}

familiar_backend_mv() {
  "${FAMILIAR_BACKEND_MV:-mv}" "$@"
}

familiar_current_summoner_id() {
  familiar_backend_require_context || return 1
  familiar_backend_summoner_id
}
