#!/usr/bin/env bash
# Run the Familiar shell test suite.
set -euo pipefail

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIRECTORY

# shellcheck source=tests/lib/test-helper.sh
source "$SCRIPT_DIRECTORY/lib/test-helper.sh"
# shellcheck source=tests/cases/lifecycle.sh
source "$SCRIPT_DIRECTORY/cases/lifecycle.sh"
# shellcheck source=tests/cases/harnesses.sh
source "$SCRIPT_DIRECTORY/cases/harnesses.sh"
# shellcheck source=tests/cases/paths.sh
source "$SCRIPT_DIRECTORY/cases/paths.sh"
# shellcheck source=tests/cases/summon.sh
source "$SCRIPT_DIRECTORY/cases/summon.sh"
# shellcheck source=tests/cases/message.sh
source "$SCRIPT_DIRECTORY/cases/message.sh"
# shellcheck source=tests/cases/dismiss.sh
source "$SCRIPT_DIRECTORY/cases/dismiss.sh"
# shellcheck source=tests/cases/status.sh
source "$SCRIPT_DIRECTORY/cases/status.sh"
# shellcheck source=tests/cases/iterm2.sh
source "$SCRIPT_DIRECTORY/cases/iterm2.sh"

main() {
  test_familiar_lifecycle
  test_familiar_harnesses
  test_familiar_paths
  test_familiar_summon
  test_familiar_message
  test_familiar_dismiss
  test_familiar_status
  test_iterm2
  test_iterm2_lifecycle
  test_iterm2_failures
  test_iterm2_origin_and_retry
  test_iterm2_auto_selection
  test_no_terminal_backend
  printf 'All Familiar tests passed.\n'
}

main "$@"
