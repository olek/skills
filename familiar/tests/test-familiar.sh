#!/usr/bin/env bash
set -euo pipefail

SKILL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly SKILL_ROOT
readonly CONFIG="$SKILL_ROOT/scripts/familiar-config.sh"
readonly LAUNCHER="$SKILL_ROOT/scripts/summon-familiar.sh"
readonly STATUS="$SKILL_ROOT/scripts/familiar-status.sh"
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
readonly FAKE_BIN="$TEST_ROOT/bin"
readonly FAKE_TMUX_STATE="$TEST_ROOT/panes.tsv"
readonly FAKE_TMUX_CALLS="$TEST_ROOT/tmux-calls.log"
readonly FAKE_TMUX_OPTIONS="$TEST_ROOT/tmux-options.tsv"
readonly FAKE_TMUX_SPLIT_ARGS="$TEST_ROOT/split-args.txt"
readonly FAKE_TMUX_LIST_COUNT="$TEST_ROOT/tmux-list-count.txt"
readonly TEST_HOME="$TEST_ROOT/home"
readonly DEFAULT_STORAGE="$TEST_HOME/.familiar"
readonly DEFAULT_ANTECHAMBER="$DEFAULT_STORAGE/antechamber"
readonly OVERRIDE_STORAGE="$TEST_ROOT/override familiar home"
readonly OVERRIDE_ANTECHAMBER="$OVERRIDE_STORAGE/antechamber"
TIMESTAMP=$(date +%y%m%d-%H%M)
readonly TIMESTAMP
FAMILIAR_HOME=''
FAMILIAR_AUTO_CLOSE_SECONDS=''
FAKE_TMUX_AUTO_CLOSE_ENABLED=0
FAKE_TMUX_FAIL_COMMAND=''
FAKE_TMUX_FAIL_SET_OPTION=''
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p -- "$FAKE_BIN" "$TEST_HOME" "$DEFAULT_ANTECHAMBER" "$OVERRIDE_ANTECHAMBER"
touch -- "$FAKE_TMUX_STATE" "$FAKE_TMUX_CALLS" "$FAKE_TMUX_OPTIONS" "$FAKE_TMUX_SPLIT_ARGS" "$FAKE_TMUX_LIST_COUNT"

touch -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"
chmod +x -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"

cat > "$FAKE_BIN/date" <<'FAKE_DATE'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == '+%y%m%d-%H%M' ]] || exit 1
printf '%s\n' "$TEST_TIMESTAMP"
FAKE_DATE
chmod +x -- "$FAKE_BIN/date"

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
      if (( FAKE_TMUX_AUTO_CLOSE_ENABLED )); then
        list_count=$(<"$FAKE_TMUX_LIST_COUNT")
        list_count=$((list_count + 1))
        printf '%s\n' "$list_count" > "$FAKE_TMUX_LIST_COUNT"
        if (( list_count >= 2 )); then
          : > "$FAKE_TMUX_STATE"
        fi
      fi
      cat -- "$FAKE_TMUX_STATE"
    elif [[ $format == *'#{@familiar_summoner_pane}'* ]]; then
      awk -F '\t' '{ print $2 "\t" $7 }' "$FAKE_TMUX_STATE"
    else
      awk -F '\t' '{ print $2 }' "$FAKE_TMUX_STATE"
    fi
    ;;
  split-window)
    [[ ${FAKE_TMUX_FAIL_COMMAND:-} != split-window ]] || exit 1
    printf '%s\n' "$@" > "$FAKE_TMUX_SPLIT_ARGS"
    printf 'pane-new\n'
    ;;
  set-option)
    [[ ${FAKE_TMUX_FAIL_SET_OPTION:-} != "$5" ]] || exit 1
    printf '%s\t%s\n' "$5" "$6" >> "$FAKE_TMUX_OPTIONS"
    ;;
  kill-pane)
    target=${3:?}
    awk -F '\t' -v target="$target" '$1 != target' "$FAKE_TMUX_STATE" > "$FAKE_TMUX_STATE.tmp"
    mv -- "$FAKE_TMUX_STATE.tmp" "$FAKE_TMUX_STATE"
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

assert_equals() {
  local -r actual=$1
  local -r expected=$2

  [[ $actual == "$expected" ]] || fail_test "expected [$expected], got [$actual]"
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

run_config() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    TEST_TIMESTAMP="$TIMESTAMP" \
    "$CONFIG" "$@"
}

run_launcher() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_OPTIONS="$FAKE_TMUX_OPTIONS" \
    FAKE_TMUX_SPLIT_ARGS="$FAKE_TMUX_SPLIT_ARGS" \
    FAKE_TMUX_FAIL_COMMAND="$FAKE_TMUX_FAIL_COMMAND" \
    FAKE_TMUX_FAIL_SET_OPTION="$FAKE_TMUX_FAIL_SET_OPTION" \
    TEST_TIMESTAMP="$TIMESTAMP" \
    "$LAUNCHER" "$@"
}

run_status() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_OPTIONS="$FAKE_TMUX_OPTIONS" \
    FAKE_TMUX_SPLIT_ARGS="$FAKE_TMUX_SPLIT_ARGS" \
    FAKE_TMUX_LIST_COUNT="$FAKE_TMUX_LIST_COUNT" \
    FAMILIAR_AUTO_CLOSE_SECONDS="$FAMILIAR_AUTO_CLOSE_SECONDS" \
    FAKE_TMUX_AUTO_CLOSE_ENABLED="$FAKE_TMUX_AUTO_CLOSE_ENABLED" \
    "$STATUS" "$@"
}

request_path_for() {
  run_config --request-path --name "$1"
}

response_path_for() {
  run_config --response-path --name "$1"
}

create_request() {
  local -r familiar_name=$1
  local -r storage_directory=$2
  local request_file="$storage_directory/antechamber/$familiar_name.md"

  printf 'Test request for %s.\n' "$familiar_name" > "$request_file"
  printf '%s\n' "$request_file"
}

reset_fake_tmux() {
  : > "$FAKE_TMUX_STATE"
  : > "$FAKE_TMUX_CALLS"
  : > "$FAKE_TMUX_OPTIONS"
  : > "$FAKE_TMUX_SPLIT_ARGS"
  : > "$FAKE_TMUX_LIST_COUNT"
}

# A managed Familiar pane's metadata, one row per pane:
#   pane_id  familiar  bare_name  timestamp  harness  storage  summoner  pane_dead
write_pane() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$FAKE_TMUX_STATE"
}

work_directory="$TEST_ROOT/familiar dir's space"
mkdir -p -- "$work_directory"

default_name='date-derived-familiar'
default_request=$(create_request "$default_name" "$DEFAULT_STORAGE")
default_timestamped_request="$DEFAULT_STORAGE/$TIMESTAMP-fmrq-$default_name.md"
default_response=$(response_path_for "$default_name")
assert_equals "$(run_config --directory)" "$DEFAULT_STORAGE"
assert_equals "$(run_config --antechamber-directory)" "$DEFAULT_ANTECHAMBER"
assert_equals "$(run_config --session-name --name "$default_name")" "$TIMESTAMP-fm-$default_name"
assert_equals "$default_request" "$(run_config --request-path --name "$default_name")"
assert_equals "$default_response" "$DEFAULT_STORAGE/$TIMESTAMP-fmrs-$default_name.md"
assert_file_not_contains "$default_request" "$default_response"
assert_file_not_contains "$default_request" 'completion-delivery contract'
assert_equals "$(run_config --session-name --name '260918-task')" "$TIMESTAMP-fm-260918-task"

FAMILIAR_HOME="$OVERRIDE_STORAGE"
override_name='environment-override'
override_request=$(create_request "$override_name" "$OVERRIDE_STORAGE")
override_timestamped_request="$OVERRIDE_STORAGE/$TIMESTAMP-fmrq-$override_name.md"
override_response=$(response_path_for "$override_name")
assert_equals "$(run_config --directory)" "$OVERRIDE_STORAGE"
assert_equals "$(run_config --antechamber-directory)" "$OVERRIDE_ANTECHAMBER"
assert_equals "$override_request" "$(run_config --request-path --name "$override_name")"
assert_equals "$override_response" "$OVERRIDE_STORAGE/$TIMESTAMP-fmrs-$override_name.md"

reset_fake_tmux
override_launch_output=$(run_launcher --name "$override_name" --cwd "$work_directory" --harness claude)
override_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$override_command" "--name $(shell_quote "$TIMESTAMP-fm-$override_name")"
assert_contains "$override_command" "The resolved response path is $override_response"
assert_contains "$override_launch_output" "request: $override_timestamped_request"
assert_contains "$override_launch_output" "response: $override_response"
[[ ! -e $override_request ]] || fail_test 'expected the staged override request to be promoted'
[[ -f $override_timestamped_request ]] || fail_test 'expected the timestamped override request to exist'

FAMILIAR_HOME=''
reset_fake_tmux
default_launch_output=$(run_launcher --name "$default_name" --cwd "$work_directory")
default_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
expected_prompt="Read and follow the request at $default_timestamped_request. The resolved response path is $default_response. Work only within its stated scope. Do not create $default_response until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents (cheaper models are fine), but make every file change yourself."
assert_contains "$default_command" 'exec codex --no-alt-screen --approve-for-me'
assert_contains "$default_command" "--config $(shell_quote 'tui.status_line=["model-with-reasoning","approval-mode","context-used","context-window-size"]')"
assert_contains "$default_command" "--cd $(shell_quote "$work_directory")"
assert_contains "$default_command" "$(shell_quote "$expected_prompt")"
assert_not_contains "$default_command" '--task '
assert_not_contains "$default_command" '--response '
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar\t1'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t'"$default_name"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_timestamp\t'"$TIMESTAMP"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_home\t'"$DEFAULT_STORAGE"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_summoner_pane\t%1'
assert_file_not_contains "$FAKE_TMUX_OPTIONS" '@familiar_task'
assert_file_not_contains "$FAKE_TMUX_OPTIONS" '@familiar_response'
assert_contains "$default_launch_output" 'pane-new'
assert_contains "$default_launch_output" "request: $default_timestamped_request"
assert_contains "$default_launch_output" "response: $default_response"
[[ ! -e $default_request ]] || fail_test 'expected the staged request to be promoted'
[[ -f $default_timestamped_request ]] || fail_test 'expected the timestamped request to exist'

codex_name='codex-model-selection'
create_request "$codex_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
run_launcher --name "$codex_name" --cwd "$work_directory" --harness codex --model "gpt model's id" --effort high >/dev/null
codex_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$codex_command" "--model $(shell_quote "gpt model's id")"
assert_contains "$codex_command" "--config $(shell_quote 'model_reasoning_effort=high')"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'

claude_name='claude-model-selection'
create_request "$claude_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
run_launcher --name "$claude_name" --cwd "$work_directory" --harness claude --model "claude model's id" --effort xhigh >/dev/null
claude_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$claude_command" 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1'
assert_contains "$claude_command" 'exec claude --permission-mode auto'
assert_contains "$claude_command" "--name $(shell_quote "$TIMESTAMP-fm-$claude_name")"
assert_contains "$claude_command" "--model $(shell_quote "claude model's id")"
assert_contains "$claude_command" "--effort $(shell_quote xhigh)"
assert_not_contains "$claude_command" 'codex'
assert_not_contains "$claude_command" '--approve-for-me'
assert_not_contains "$claude_command" '--no-alt-screen'
assert_not_contains "$claude_command" '--cd'
assert_not_contains "$claude_command" '--config'
assert_not_contains "$claude_command" 'model_reasoning_effort'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t'"$claude_name"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_timestamp\t'"$TIMESTAMP"

invalid_name_case=0
for invalid_name in \
  'fm-task' \
  'fmrq-task' \
  'fmrs-task' \
  'Bad-name' \
  'name_with_underscore' \
  'name with spaces'; do
  invalid_name_case=$((invalid_name_case + 1))
  reset_fake_tmux
  if run_launcher --name "$invalid_name" --cwd "$work_directory" >/dev/null 2>&1; then
    fail_test "expected launcher failure for invalid name: $invalid_name"
  fi
  assert_no_split
done

reset_fake_tmux
if run_launcher --task "$default_request" --response "$default_response" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected the removed --task/--response interface to fail'
fi
assert_no_split

reset_fake_tmux
if run_launcher --name 'invalid-harness' --cwd "$work_directory" --harness unknown >/dev/null 2>&1; then
  fail_test 'expected an unknown harness to fail'
fi
assert_no_split

reset_fake_tmux
if run_launcher --name 'duplicate-harness' --cwd "$work_directory" --harness claude --harness codex >/dev/null 2>&1; then
  fail_test 'expected duplicate harness options to fail'
fi
assert_no_split

reset_fake_tmux
if run_launcher --name 'missing-harness' --cwd "$work_directory" --harness >/dev/null 2>&1; then
  fail_test 'expected a missing harness value to fail'
fi
assert_no_split

reset_fake_tmux
if run_launcher --name 'invalid-effort' --cwd "$work_directory" --harness claude --effort ultra >/dev/null 2>&1; then
  fail_test 'expected unsupported Claude effort to fail'
fi
assert_no_split

other_summoner_name='other-summoner-allowed'
create_request "$other_summoner_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
write_pane '%2' '1' 'other-summoner-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%99' '0'
run_launcher --name "$other_summoner_name" --cwd "$work_directory" >/dev/null
assert_file_contains "$FAKE_TMUX_CALLS" 'split-window'

guard_name='guarded-launch'
guard_request=$(create_request "$guard_name" "$DEFAULT_STORAGE")
reset_fake_tmux
write_pane '%2' '1' 'existing-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%1' '0'
if run_launcher --name "$guard_name" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected an existing managed Familiar to block the launch'
fi
assert_no_split
[[ -f $guard_request ]] || fail_test 'expected a blocked launch to preserve the staged request'

collision_name='durable-collision'
collision_request=$(create_request "$collision_name" "$DEFAULT_STORAGE")
touch -- "$DEFAULT_STORAGE/$TIMESTAMP-fmrq-$collision_name.md"
reset_fake_tmux
if run_launcher --name "$collision_name" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected an existing durable request to block the launch'
fi
assert_no_split
[[ -f $collision_request ]] || fail_test 'expected a collision to preserve the staged request'

split_failure_name='split-failure'
split_failure_request=$(create_request "$split_failure_name" "$DEFAULT_STORAGE")
reset_fake_tmux
FAKE_TMUX_FAIL_COMMAND='split-window'
if run_launcher --name "$split_failure_name" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected a split-window failure'
fi
FAKE_TMUX_FAIL_COMMAND=''
[[ -f $split_failure_request ]] || fail_test 'expected split failure to restore the staged request'
[[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-fmrq-$split_failure_name.md ]] || fail_test 'expected no durable request after split failure'

metadata_failure_name='metadata-failure'
metadata_failure_request=$(create_request "$metadata_failure_name" "$DEFAULT_STORAGE")
reset_fake_tmux
FAKE_TMUX_FAIL_SET_OPTION='@familiar_home'
if run_launcher --name "$metadata_failure_name" --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected a metadata failure'
fi
FAKE_TMUX_FAIL_SET_OPTION=''
[[ -f $metadata_failure_request ]] || fail_test 'expected metadata failure to restore the staged request'
[[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-fmrq-$metadata_failure_name.md ]] || fail_test 'expected no durable request after metadata failure'
assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'

status_storage="$OVERRIDE_STORAGE"
FAMILIAR_HOME="$status_storage"
delivered_name='status-delivered'
awaiting_name='status-awaiting'
invalid_name='status-invalid'
dead_name='status-dead'
historical_name='historical-status'
historical_timestamp='250101-1234'
delivered_response=$(response_path_for "$delivered_name")
invalid_response=$(response_path_for "$invalid_name")
historical_response="$status_storage/$historical_timestamp-fmrs-$historical_name.md"
touch -- "$delivered_response" "$historical_response"
mkdir -p -- "$invalid_response"
reset_fake_tmux
write_pane '%4' '1' "$delivered_name" "$TIMESTAMP" codex "$status_storage" '%1' '0'
write_pane '%5' '1' "$awaiting_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
write_pane '%7' '1' "$invalid_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
write_pane '%8' '1' "$dead_name" "$TIMESTAMP" codex "$status_storage" '%1' '1'
write_pane '%9' '1' "$historical_name" "$historical_timestamp" claude "$status_storage" '%1' '0'
write_pane '%15' '1' 'other-summoner' "$TIMESTAMP" codex "$status_storage" '%99' '0'
FAMILIAR_HOME=''
status_output=$(run_status)
assert_contains "$status_output" 'Managed Familiar: status-delivered (codex, pane %4, response delivered)'
assert_contains "$status_output" 'Managed Familiar: status-awaiting (claude, pane %5, awaiting response)'
assert_contains "$status_output" 'Managed Familiar: status-invalid (claude, pane %7, response path invalid)'
assert_contains "$status_output" 'Managed Familiar: status-dead (codex, pane %8, ended without response)'
assert_contains "$status_output" "  request: $status_storage/$historical_timestamp-fmrq-$historical_name.md"
assert_contains "$status_output" "  response: $historical_response"
assert_not_contains "$status_output" 'other-summoner'
FAMILIAR_HOME="$status_storage"

reset_fake_tmux
write_pane '%10' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
wait_output=$(run_status --wait --timeout 10)
assert_not_contains "$wait_output" 'Timed out'
assert_not_contains "$wait_output" 'Auto-close'
assert_contains "$wait_output" 'response delivered'

reset_fake_tmux
write_pane '%11' '1' "$invalid_name" "$TIMESTAMP" codex "$status_storage" '%1' '0'
wait_output=$(run_status --wait --timeout 10)
assert_not_contains "$wait_output" 'Timed out'
assert_contains "$wait_output" 'response path invalid'

reset_fake_tmux
write_pane '%12' '1' "$awaiting_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
wait_output=$(run_status --wait --timeout 0)
assert_contains "$wait_output" 'Timed out after 0 seconds'
assert_contains "$wait_output" 'awaiting response'

reset_fake_tmux
write_pane '%13' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
FAKE_TMUX_AUTO_CLOSE_ENABLED=1
wait_output=$(run_status --wait --auto-close)
FAKE_TMUX_AUTO_CLOSE_ENABLED=0
assert_not_contains "$wait_output" 'Auto-closed Familiar pane'
assert_contains "$wait_output" 'Auto-close ended: the Familiar pane is closed.'
assert_contains "$wait_output" 'No managed Familiar exists for this summoning agent instance.'

reset_fake_tmux
write_pane '%14' '1' "$delivered_name" "$TIMESTAMP" claude "$status_storage" '%1' '0'
FAMILIAR_AUTO_CLOSE_SECONDS='01'
wait_output=$(run_status --wait --auto-close)
FAMILIAR_AUTO_CLOSE_SECONDS=''
assert_contains "$wait_output" 'Auto-closed Familiar pane %14 after 1 seconds of user inspection.'
assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'
assert_contains "$wait_output" 'No managed Familiar exists for this summoning agent instance.'

reset_fake_tmux
invalid_output=''
if invalid_output=$(run_status --auto-close 2>&1); then
  fail_test 'expected --auto-close without --wait to fail'
fi
assert_contains "$invalid_output" '--auto-close requires --wait'

reset_fake_tmux
invalid_output=''
if invalid_output=$(run_status --wait --auto-close 1 2>&1); then
  fail_test 'expected a value after --auto-close to fail'
fi
assert_contains "$invalid_output" '--auto-close does not take a value'

reset_fake_tmux
FAMILIAR_AUTO_CLOSE_SECONDS='61'
if run_status --wait --auto-close >/dev/null 2>&1; then
  fail_test 'expected an auto-close interval over 60 seconds to fail'
fi
FAMILIAR_AUTO_CLOSE_SECONDS=''

reset_fake_tmux
if run_status --wait --auto-close --auto-close >/dev/null 2>&1; then
  fail_test 'expected duplicate --auto-close options to fail'
fi

reset_fake_tmux
if run_status --auto-close --timeout 0 >/dev/null 2>&1; then
  fail_test 'expected --auto-close without explicit --wait to fail'
fi

printf 'All Familiar tests passed.\n'
