#!/usr/bin/env bash
# Load the terminal backend used by Familiar lifecycle commands.

FAMILIAR_BACKEND_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/backends" && pwd)
readonly FAMILIAR_BACKEND_DIRECTORY

case ${FAMILIAR_BACKEND:-auto} in
  auto)
    if [[ -n ${TMUX:-} ]]; then
      source "$FAMILIAR_BACKEND_DIRECTORY/tmux.sh"
    elif [[ -n ${ITERM_SESSION_ID:-} ]]; then
      source "$FAMILIAR_BACKEND_DIRECTORY/iterm2.sh"
    else
      printf 'No supported Familiar terminal backend is available; run inside tmux or a local iTerm2 session.\n' >&2
      return 1
    fi
    ;;
  tmux) source "$FAMILIAR_BACKEND_DIRECTORY/tmux.sh" ;;
  iterm2) source "$FAMILIAR_BACKEND_DIRECTORY/iterm2.sh" ;;
  *) printf 'Unknown Familiar backend: %s\n' "$FAMILIAR_BACKEND" >&2; return 1 ;;
esac
