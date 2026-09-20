#!/usr/bin/env bash
set -euo pipefail

SKILL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly SKILL_ROOT
readonly LAUNCHER="$SKILL_ROOT/scripts/summon-familiar.sh"
readonly STATUS="$SKILL_ROOT/scripts/familiar-status.sh"
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
readonly FAKE_BIN="$TEST_ROOT/bin"
readonly FAKE_TMUX_STATE="$TEST_ROOT/panes.tsv"
readonly FAKE_TMUX_CALLS="$TEST_ROOT/tmux-calls.log"
readonly FAKE_TMUX_OPTIONS="$TEST_ROOT/tmux-options.tsv"
readonly FAKE_TMUX_SPLIT_ARGS="$TEST_ROOT/split-args.txt"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p -- "$FAKE_BIN"
touch -- "$FAKE_TMUX_STATE" "$FAKE_TMUX_CALLS" "$FAKE_TMUX_OPTIONS" "$FAKE_TMUX_SPLIT_ARGS"

touch -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"
chmod +x -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"

cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -euo pipefail

readonly command_name=${1:-}
printf '%s\n' "$command_name" >> "$FAKE_TMUX_CALLS"

case "$command_name" in
  display-message)
    printf 'window-1\n'
    ;;
  list-panes)
    format=${!#}
    if [[ $format == *'#{@familiar_name}'* ]]; then
      cat -- "$FAKE_TMUX_STATE"
    else
      awk -F '\t' '{ print $2 }' "$FAKE_TMUX_STATE"
    fi
    ;;
  split-window)
    printf '%s\n' "$@" > "$FAKE_TMUX_SPLIT_ARGS"
    printf 'pane-new\n'
    ;;
  set-option)
    printf '%s\t%s\n' "$5" "$6" >> "$FAKE_TMUX_OPTIONS"
    ;;
  *)
    printf 'Unexpected fake tmux command: %s\n' "$command_name" >&2
    exit 1
    ;;
esac
FAKE_TMUX
chmod +x -- "$FAKE_BIN/tmux"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local -r haystack=$1
  local -r needle=$2

  [[ $haystack == *"$needle"* ]] || fail_test "expected to find [$needle]"
}

assert_not_contains() {
  local -r haystack=$1
  local -r needle=$2

  [[ $haystack != *"$needle"* ]] || fail_test "did not expect to find [$needle]"
}

assert_file_contains() {
  local -r file=$1
  local -r needle=$2

  grep -Fq -- "$needle" "$file" || fail_test "expected $file to contain [$needle]"
}

assert_file_not_contains() {
  local -r file=$1
  local -r needle=$2

  if grep -Fq -- "$needle" "$file"; then
    fail_test "did not expect $file to contain [$needle]"
  fi
}

assert_no_split() {
  local split_count
  split_count=$(awk '$1 == "split-window" { count++ } END { print count + 0 }' "$FAKE_TMUX_CALLS")
  [[ $split_count == 0 ]] || fail_test "expected no split-window call, got $split_count"
}

shell_quote() {
  local escaped_value=$1
  escaped_value=${escaped_value//\'/\'"\'"\'}
  printf "'%s'" "$escaped_value"
}

run_launcher() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_OPTIONS="$FAKE_TMUX_OPTIONS" \
    FAKE_TMUX_SPLIT_ARGS="$FAKE_TMUX_SPLIT_ARGS" \
    "$LAUNCHER" "$@"
}

run_status() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_OPTIONS="$FAKE_TMUX_OPTIONS" \
    FAKE_TMUX_SPLIT_ARGS="$FAKE_TMUX_SPLIT_ARGS" \
    "$STATUS" "$@"
}

reset_fake_tmux() {
  : > "$FAKE_TMUX_STATE"
  : > "$FAKE_TMUX_CALLS"
  : > "$FAKE_TMUX_OPTIONS"
  : > "$FAKE_TMUX_SPLIT_ARGS"
}

# A managed Familiar pane's metadata, one row per pane:
#   pane_id  familiar  name  harness  task  response  pane_dead
write_pane() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$FAKE_TMUX_STATE"
}

work_directory="$TEST_ROOT/familiar dir's space"
mkdir -p -- "$work_directory"
request_file="$TEST_ROOT/260918-fmrq-task's review.md"
printf '%s\n' 'Test request' > "$request_file"
response_parent="$TEST_ROOT/result dir"
mkdir -p -- "$response_parent"
response="$response_parent/response file's result.md"

reset_fake_tmux
run_launcher --task "$request_file" --response "$response" --cwd "$work_directory" >/dev/null
default_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
resolved_response="$response_parent/response file's result.md"
assert_contains "$default_command" 'exec codex --no-alt-screen --approve-for-me'
assert_contains "$default_command" "--config $(shell_quote 'tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]')"
assert_contains "$default_command" "--cd $(shell_quote "$work_directory")"
assert_contains "$default_command" "$(shell_quote "Read and follow the request at $(realpath -e -- "$request_file"). Work only within its stated scope. Do not create $resolved_response until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents (cheaper models are fine), but make every file change yourself.")"

reset_fake_tmux
codex_response="$response_parent/codex result.md"
run_launcher --task "$request_file" --response "$codex_response" --cwd "$work_directory" --harness codex --model "gpt model's id" --effort high >/dev/null
codex_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$codex_command" "--model $(shell_quote "gpt model's id")"
assert_contains "$codex_command" "--config $(shell_quote 'model_reasoning_effort=high')"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'

reset_fake_tmux
claude_response="$response_parent/claude result.md"
run_launcher --task "$request_file" --response "$claude_response" --cwd "$work_directory" --harness claude --model "claude model's id" --effort xhigh >/dev/null
claude_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$claude_command" 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1'
assert_contains "$claude_command" 'exec claude --permission-mode auto'
assert_contains "$claude_command" "--name $(shell_quote '260918-fm-task-s-review')"
assert_contains "$claude_command" "--model $(shell_quote "claude model's id")"
assert_contains "$claude_command" "--effort $(shell_quote xhigh)"
assert_not_contains "$claude_command" 'codex'
assert_not_contains "$claude_command" '--approve-for-me'
assert_not_contains "$claude_command" '--no-alt-screen'
assert_not_contains "$claude_command" '--cd'
assert_not_contains "$claude_command" '--config'
assert_not_contains "$claude_command" 'model_reasoning_effort'
assert_file_contains "$FAKE_TMUX_SPLIT_ARGS" "$work_directory"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tclaude'

invalid_case=0
for invalid_args in \
  "--harness unknown" \
  "--harness claude --harness codex" \
  "--harness"; do
  read -r -a invalid_argv <<< "$invalid_args"
  invalid_case=$((invalid_case + 1))
  reset_fake_tmux
  if run_launcher --task "$request_file" --response "$response_parent/invalid-$invalid_case.md" --cwd "$work_directory" "${invalid_argv[@]}" >/dev/null 2>&1; then
    fail_test "expected launcher failure for: $invalid_args"
  fi
  assert_no_split
done

reset_fake_tmux
if run_launcher --task "$request_file" --response "$response_parent/invalid-effort.md" --cwd "$work_directory" --harness claude --effort ultra >/dev/null 2>&1; then
  fail_test 'expected unsupported Claude effort to fail'
fi
assert_no_split

reset_fake_tmux
write_pane '%2' '1' 'existing familiar' 'codex' '/task' '/response' '0'
if run_launcher --task "$request_file" --response "$response_parent/blocked.md" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected an existing managed Familiar to block the launch'
fi
assert_no_split

reset_fake_tmux
metadata_response="$response_parent/metadata.md"
run_launcher --task "$request_file" --response "$metadata_response" --cwd "$work_directory" --harness claude >/dev/null
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar\t1'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t260918-fm-task-s-review'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tclaude'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_task\t'"$(realpath -e -- "$request_file")"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_response\t'"$response_parent/metadata.md"
assert_file_not_contains "$FAKE_TMUX_OPTIONS" '@minion_agent'
assert_file_not_contains "$FAKE_TMUX_OPTIONS" '@codex'

delivered_response="$response_parent/delivered.md"
touch -- "$delivered_response"
invalid_response="$response_parent/invalid-path"
mkdir -p -- "$invalid_response"
reset_fake_tmux
write_pane '%4' '1' 'codex familiar' 'codex' '/task-codex' "$delivered_response" '0'
write_pane '%5' '1' 'claude familiar' 'claude' '/task-claude' '/missing-response' '0'
write_pane '%7' '1' 'invalid familiar' 'claude' '/task-invalid' "$invalid_response" '0'
write_pane '%8' '1' 'dead familiar' 'codex' '/task-dead' '/dead-response' '1'
status_output=$(run_status)
assert_contains "$status_output" 'Managed Familiar: codex familiar (codex, pane %4, response delivered)'
assert_contains "$status_output" 'Managed Familiar: claude familiar (claude, pane %5, awaiting response)'
assert_contains "$status_output" 'Managed Familiar: invalid familiar (claude, pane %7, response path invalid)'
assert_contains "$status_output" 'Managed Familiar: dead familiar (codex, pane %8, ended without response)'

reset_fake_tmux
write_pane '%10' '1' 'delivered familiar' 'claude' '/task' "$delivered_response" '0'
wait_output=$(run_status --wait --timeout 10)
assert_not_contains "$wait_output" 'Timed out'
assert_contains "$wait_output" 'response delivered'

reset_fake_tmux
write_pane '%11' '1' 'failed familiar' 'codex' '/task' "$invalid_response" '0'
wait_output=$(run_status --wait --timeout 10)
assert_not_contains "$wait_output" 'Timed out'
assert_contains "$wait_output" 'response path invalid'

reset_fake_tmux
write_pane '%12' '1' 'waiting familiar' 'claude' '/task' '/not-delivered' '0'
wait_output=$(run_status --wait --timeout 0)
assert_contains "$wait_output" 'Timed out after 0 seconds'
assert_contains "$wait_output" 'awaiting response'

printf 'All Familiar tests passed.\n'
