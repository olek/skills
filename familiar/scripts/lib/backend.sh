#!/usr/bin/env bash
# Load the terminal backend used by Familiar lifecycle commands.

FAMILIAR_BACKEND_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/backends" && pwd)
readonly FAMILIAR_BACKEND_DIRECTORY

# Phase 1 has one deliberately fixed backend. Selection belongs to a later
# compatibility phase, after another transport has a proven implementation.
# shellcheck disable=SC1091
source "$FAMILIAR_BACKEND_DIRECTORY/tmux.sh"
