#!/usr/bin/env bash
# Verify Familiar paths, catalogs, lifecycle, messaging, dismissal, and status.
set -euo pipefail

SKILL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly SKILL_ROOT
readonly PATHS_SCRIPT="$SKILL_ROOT/scripts/paths.sh"
readonly LAUNCHER="$SKILL_ROOT/scripts/summon.sh"
readonly MESSAGE="$SKILL_ROOT/scripts/message.sh"
readonly DISMISS="$SKILL_ROOT/scripts/dismiss.sh"
readonly STATUS="$SKILL_ROOT/scripts/status.sh"
readonly MODELS="$SKILL_ROOT/scripts/models.sh"
readonly EFFORTS="$SKILL_ROOT/scripts/efforts.sh"
readonly DEFAULTS="$SKILL_ROOT/scripts/defaults.sh"
readonly HARNESS_LOADER="$SKILL_ROOT/scripts/lib/harness.sh"
readonly BACKEND_LOADER="$SKILL_ROOT/scripts/lib/backend.sh"
readonly FAMILIAR_POLICY="$SKILL_ROOT/scripts/lib/familiar.sh"
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
readonly FAKE_BIN="$TEST_ROOT/bin"
readonly FAKE_TMUX_STATE="$TEST_ROOT/panes.tsv"
readonly FAKE_TMUX_CALLS="$TEST_ROOT/tmux-calls.log"
readonly FAKE_TMUX_OPTIONS="$TEST_ROOT/tmux-options.tsv"
readonly FAKE_TMUX_SPLIT_ARGS="$TEST_ROOT/split-args.txt"
readonly FAKE_TMUX_LIST_COUNT="$TEST_ROOT/tmux-list-count.txt"
readonly FAKE_TMUX_SEND_KEYS_ARGS="$TEST_ROOT/send-keys-args.txt"
readonly FAKE_TMUX_SEND_KEYS_COUNT="$TEST_ROOT/send-keys-count.txt"
readonly FAKE_SLEEP_ARGS="$TEST_ROOT/sleep-args.txt"
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
FAKE_TMUX_FAIL_SEND_KEYS=''
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p -- "$FAKE_BIN" "$TEST_HOME" "$DEFAULT_ANTECHAMBER" "$OVERRIDE_ANTECHAMBER"
touch -- "$FAKE_TMUX_STATE" "$FAKE_TMUX_CALLS" "$FAKE_TMUX_OPTIONS" "$FAKE_TMUX_SPLIT_ARGS" "$FAKE_TMUX_LIST_COUNT" "$FAKE_TMUX_SEND_KEYS_ARGS" "$FAKE_TMUX_SEND_KEYS_COUNT" "$FAKE_SLEEP_ARGS"

touch -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"
chmod +x -- "$FAKE_BIN/codex" "$FAKE_BIN/claude"

cat > "$FAKE_BIN/opencode" <<'FAKE_OPENCODE'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == models ]] && printf 'provider/opencode-test-model\n'
FAKE_OPENCODE
chmod +x -- "$FAKE_BIN/opencode"

cat > "$FAKE_BIN/agy" <<'FAKE_ANTIGRAVITY'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == models ]] && printf 'antigravity-test-model\n'
FAKE_ANTIGRAVITY
chmod +x -- "$FAKE_BIN/agy"

cat > "$FAKE_BIN/date" <<'FAKE_DATE'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == '+%y%m%d-%H%M' ]] || exit 1
printf '%s\n' "$TEST_TIMESTAMP"
FAKE_DATE
chmod +x -- "$FAKE_BIN/date"

cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n ${FAKE_SLEEP_ARGS:-} ]]; then
  printf 'sleep\n' >> "$FAKE_TMUX_CALLS"
  printf '%s\n' "$@" >> "$FAKE_SLEEP_ARGS"
  exit 0
fi

exec /usr/bin/sleep "$@"
FAKE_SLEEP
chmod +x -- "$FAKE_BIN/sleep"

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
  send-keys)
    send_keys_count=$(<"$FAKE_TMUX_SEND_KEYS_COUNT")
    send_keys_count=$((send_keys_count + 1))
    printf '%s\n' "$send_keys_count" > "$FAKE_TMUX_SEND_KEYS_COUNT"
    printf '%s\n' "$@" >> "$FAKE_TMUX_SEND_KEYS_ARGS"
    printf '%s\n' 'END_CALL' >> "$FAKE_TMUX_SEND_KEYS_ARGS"
    [[ ${FAKE_TMUX_FAIL_SEND_KEYS:-} != "$send_keys_count" ]] || exit 1
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

assert_shell_purpose_comments() {
  local shell_file
  local shebang
  local purpose_comment

  while IFS= read -r shell_file; do
    shebang=$(sed -n '1p' "$SKILL_ROOT/$shell_file")
    purpose_comment=$(sed -n '2p' "$SKILL_ROOT/$shell_file")
    [[ $shebang == '#!'* ]] || fail_test "expected a shebang in $shell_file"
    [[ $purpose_comment == '# '* ]] || fail_test "expected a purpose comment after the shebang in $shell_file"
  done < <(cd -- "$SKILL_ROOT" && rg --files -g '*.sh' | sort)
}

assert_no_split() {
  local split_count
  split_count=$(awk '$1 == "split-window" { count++ } END { print count + 0 }' "$FAKE_TMUX_CALLS")
  readonly split_count
  [[ $split_count == 0 ]] || fail_test "expected no split-window call, got $split_count"
}

assert_no_raw_tmux_examples() {
  local -r file=$1
  local raw_examples

  if raw_examples=$(rg -n '^[[:space:]]*tmux[[:space:]]' "$file"); then
    fail_test "did not expect raw tmux command examples in $file: $raw_examples"
  fi
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
    "$PATHS_SCRIPT" "$@"
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
    FAKE_TMUX_SEND_KEYS_ARGS="$FAKE_TMUX_SEND_KEYS_ARGS" \
    FAKE_TMUX_SEND_KEYS_COUNT="$FAKE_TMUX_SEND_KEYS_COUNT" \
    FAKE_TMUX_FAIL_SEND_KEYS="$FAKE_TMUX_FAIL_SEND_KEYS" \
    FAKE_TMUX_AUTO_CLOSE_ENABLED="$FAKE_TMUX_AUTO_CLOSE_ENABLED" \
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

run_message() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_SEND_KEYS_ARGS="$FAKE_TMUX_SEND_KEYS_ARGS" \
    FAKE_TMUX_SEND_KEYS_COUNT="$FAKE_TMUX_SEND_KEYS_COUNT" \
    FAKE_TMUX_FAIL_SEND_KEYS="$FAKE_TMUX_FAIL_SEND_KEYS" \
    FAKE_SLEEP_ARGS="$FAKE_SLEEP_ARGS" \
    FAKE_TMUX_AUTO_CLOSE_ENABLED="$FAKE_TMUX_AUTO_CLOSE_ENABLED" \
    "$MESSAGE" "$@"
}

run_dismiss() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    TMUX=1 \
    TMUX_PANE='%1' \
    FAKE_TMUX_STATE="$FAKE_TMUX_STATE" \
    FAKE_TMUX_CALLS="$FAKE_TMUX_CALLS" \
    FAKE_TMUX_AUTO_CLOSE_ENABLED="$FAKE_TMUX_AUTO_CLOSE_ENABLED" \
    "$DISMISS" "$@"
}

run_models() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    "$MODELS" "$@"
}

run_efforts() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    "$EFFORTS" "$@"
}

run_defaults() {
  env \
    PATH="$FAKE_BIN:$PATH" \
    "$DEFAULTS" "$@"
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
  local -r request_file="$storage_directory/antechamber/$familiar_name.md"

  printf 'Test request for %s.\n' "$familiar_name" > "$request_file"
  printf '%s\n' "$request_file"
}

reset_fake_tmux() {
  : > "$FAKE_TMUX_STATE"
  : > "$FAKE_TMUX_CALLS"
  : > "$FAKE_TMUX_OPTIONS"
  : > "$FAKE_TMUX_SPLIT_ARGS"
  : > "$FAKE_TMUX_LIST_COUNT"
  : > "$FAKE_TMUX_SEND_KEYS_ARGS"
  : > "$FAKE_TMUX_SEND_KEYS_COUNT"
  : > "$FAKE_SLEEP_ARGS"
  printf '0\n' > "$FAKE_TMUX_SEND_KEYS_COUNT"
}

[[ -x $LAUNCHER ]] || fail_test 'expected the canonical Familiar summon script to be executable'
assert_shell_purpose_comments
[[ ! -e $SKILL_ROOT/scripts/summon-familiar.sh ]] || fail_test 'did not expect the old summon script name to remain'
[[ -x $MESSAGE ]] || fail_test 'expected the Familiar message script to be executable'
[[ -x $DISMISS ]] || fail_test 'expected the Familiar dismissal script to be executable'
[[ -x $HARNESS_LOADER ]] || fail_test 'expected the source-only harness loader in scripts/lib'
[[ -f $BACKEND_LOADER ]] || fail_test 'expected the source-only backend loader in scripts/lib'
[[ -f $FAMILIAR_POLICY ]] || fail_test 'expected the generic Familiar policy in scripts/lib'
[[ ! -e $SKILL_ROOT/scripts/familiar-harness.sh ]] || fail_test 'did not expect the redundant root harness loader to remain'
[[ ! -e $SKILL_ROOT/scripts/lib/familiar-harness.sh ]] || fail_test 'did not expect the redundant library harness name to remain'
for redundant_script in familiar-defaults.sh familiar-dismiss.sh familiar-efforts.sh familiar-message.sh familiar-models.sh familiar-paths.sh familiar-status.sh familiar-summon.sh; do
  [[ ! -e $SKILL_ROOT/scripts/$redundant_script ]] || fail_test "did not expect redundant script name to remain: $redundant_script"
done
[[ ! -e $SKILL_ROOT/scripts/lib/familiar-pane.sh ]] || fail_test 'did not expect the redundant library pane name to remain'
[[ ! -e $SKILL_ROOT/scripts/lib/pane.sh ]] || fail_test 'did not expect the tmux-coupled pane helper to remain'
[[ ! -e $SKILL_ROOT/scripts/lib/target.sh ]] || fail_test 'did not expect the superseded lifecycle helper to remain'
[[ ! -d $SKILL_ROOT/scripts/harnesses ]] || fail_test 'expected the old harness directory to be moved'
[[ -f $SKILL_ROOT/scripts/lib/harnesses/codex.sh ]] || fail_test 'expected the codex harness filename to remain unchanged'
[[ ! -e $SKILL_ROOT/scripts/lib/harnesses/codex-lib.sh ]] || fail_test 'did not expect the superseded harness suffix'
assert_file_contains "$SKILL_ROOT/SKILL.md" 'message.sh --message'
assert_file_contains "$SKILL_ROOT/SKILL.md" 'dismiss.sh'
assert_no_raw_tmux_examples "$SKILL_ROOT/SKILL.md"

# Generic lifecycle policy is tested against a backend double. Adapter command
# checks below retain coverage for tmux metadata and delivery mechanics.
generic_policy_output=$(FAKE_FAMILIAR_ROWS=$'familiar-1\tfake-familiar\tstamp\tcodex\thome\t0' bash -c '
  set -euo pipefail
  familiar_backend_list_familiars() {
    printf "%s\\n" "$FAKE_FAMILIAR_ROWS"
  }
  familiar_backend_close_familiar() {
    printf "closed:%s\\n" "$1"
  }
  source "$1"
  name=""
  familiar=""
  familiar_resolve_live_familiar name familiar summoner
  printf "resolved:%s:%s\\n" "$name" "$familiar"
  familiar_close_familiar "$familiar"
' -- "$FAMILIAR_POLICY" \
  2>&1) || fail_test 'expected generic Familiar policy to resolve a fake Familiar'
assert_equals "$generic_policy_output" $'resolved:fake-familiar:familiar-1\nclosed:familiar-1'

generic_multiple_output=''
if generic_multiple_output=$(FAKE_FAMILIAR_ROWS=$'familiar-1\tfirst\tstamp\tcodex\thome\t0\nfamiliar-2\tsecond\tstamp\tcodex\thome\t0' bash -c '
  set -euo pipefail
  familiar_backend_list_familiars() { printf "%s\\n" "$FAKE_FAMILIAR_ROWS"; }
  source "$1"
  name=""; familiar=""
  familiar_resolve_live_familiar name familiar summoner
' -- "$FAMILIAR_POLICY" 2>&1); then
  fail_test 'expected generic Familiar policy to reject multiple live Familiars'
fi
assert_contains "$generic_multiple_output" 'Multiple live managed Familiars are associated with summoner summoner.'

# Verify harness discovery and each harness's advertised launch choices.
discovered_harnesses=$(bash -c 'source "$1"; familiar_harness_all' -- "$HARNESS_LOADER")
assert_contains "$discovered_harnesses" 'codex'
assert_contains "$discovered_harnesses" 'claude'
assert_contains "$discovered_harnesses" 'opencode'
assert_contains "$discovered_harnesses" 'antigravity'

unknown_harness_output=''
if unknown_harness_output=$(bash -c 'source "$1"; familiar_harness_load "$2"' -- "$HARNESS_LOADER" unknown 2>&1); then
  fail_test 'expected loading an unknown harness to fail'
fi
assert_contains "$unknown_harness_output" 'Unknown Familiar harness: unknown'

harness_copy="$TEST_ROOT/harness-copy"
mkdir -p -- "$harness_copy/lib/harnesses"
cp -- "$HARNESS_LOADER" "$harness_copy/lib/harness.sh"
cp -- "$SKILL_ROOT/scripts/lib/harnesses/codex.sh" "$harness_copy/lib/harnesses/codex.sh"
cp -- "$SKILL_ROOT/scripts/lib/harnesses/claude.sh" "$harness_copy/lib/harnesses/claude.sh"
cat > "$harness_copy/lib/harnesses/scratch.sh" <<'SCRATCH_HARNESS'
#!/usr/bin/env bash

familiar_harness_executable() {
  printf 'scratch\n'
}
SCRATCH_HARNESS
scratch_harnesses=$(bash -c 'source "$1"; familiar_harness_all' -- "$harness_copy/lib/harness.sh")
assert_contains "$scratch_harnesses" 'scratch'
loaded_codex_executable=$(
  bash -c 'source "$1"; familiar_harness_load codex; familiar_harness_executable' -- "$harness_copy/lib/harness.sh"
)
assert_equals "$loaded_codex_executable" 'codex'
loaded_scratch_executable=$(
  bash -c 'source "$1"; familiar_harness_load scratch; familiar_harness_executable' -- "$harness_copy/lib/harness.sh"
)
assert_equals "$loaded_scratch_executable" 'scratch'

for default_intent_harness in opencode antigravity; do
  for intent in planning implementation review; do
    assert_equals "$(run_defaults --harness "$default_intent_harness" --intent "$intent")" $'model=default\neffort=default'
  done
done

opencode_models=$(run_models --harness opencode)
assert_contains "$opencode_models" 'provider/opencode-test-model'
opencode_efforts_output=''
if opencode_efforts_output=$(run_efforts --harness opencode 2>&1); then
  fail_test 'expected OpenCode effort discovery to report unsupported launch-time overrides'
fi
assert_contains "$opencode_efforts_output" 'does not support launch-time effort overrides'
opencode_effort_command_output=''
if opencode_effort_command_output=$(
  bash -c 'source "$1"; familiar_harness_load opencode; familiar_harness_build_command /tmp session prompt model high config' \
    -- "$HARNESS_LOADER" 2>&1
); then
  fail_test 'expected OpenCode command construction with an effort override to fail'
fi
assert_contains "$opencode_effort_command_output" 'does not support launch-time effort overrides'
antigravity_models=$(run_models --harness antigravity)
assert_contains "$antigravity_models" 'antigravity-test-model'
antigravity_efforts=$(run_efforts --harness antigravity)
assert_contains "$antigravity_efforts" 'high'

codex_models=$(run_models --harness codex)
assert_contains "$codex_models" 'gpt-5.6-luna'
assert_not_contains "$codex_models" 'default'
codex_efforts=$(run_efforts --harness codex)
assert_contains "$codex_efforts" 'ultra'
assert_not_contains "$codex_efforts" 'default'
codex_planning_defaults=$(run_defaults --harness codex --intent planning)
assert_equals "$codex_planning_defaults" $'model=gpt-5.6-sol\neffort=medium'
claude_models=$(run_models --harness claude)
assert_contains "$claude_models" 'sonnet'
claude_efforts=$(run_efforts --harness claude)
assert_not_contains "$claude_efforts" 'ultra'
codex_implementation_defaults=$(run_defaults --harness codex --intent implementation)
assert_equals "$codex_implementation_defaults" $'model=gpt-5.6-terra\neffort=medium'
codex_review_defaults=$(run_defaults --harness codex --intent review)
assert_equals "$codex_review_defaults" $'model=gpt-5.6-sol\neffort=medium'
claude_planning_defaults=$(run_defaults --harness claude --intent planning)
assert_equals "$claude_planning_defaults" $'model=opus\neffort=medium'
claude_implementation_defaults=$(run_defaults --harness claude --intent implementation)
assert_equals "$claude_implementation_defaults" $'model=sonnet\neffort=high'
claude_review_defaults=$(run_defaults --harness claude --intent review)
assert_equals "$claude_review_defaults" $'model=opus\neffort=medium'

legacy_models_output=''
if legacy_models_output=$(run_models --harness codex --efforts 2>&1); then
  fail_test 'expected the old multi-mode models contract to fail'
fi
assert_contains "$legacy_models_output" 'Unknown option: --efforts'

# A managed Familiar pane's metadata, one row per pane:
#   pane_id  familiar  bare_name  timestamp  harness  storage  summoner  pane_dead
write_pane() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$FAKE_TMUX_STATE"
}

# Verify storage paths and successful launch lifecycle transitions.
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

# --request-path creates the antechamber directory so the summoning agent need not.
fresh_home="$TEST_ROOT/fresh-home"
fresh_antechamber="$fresh_home/antechamber"
[[ ! -e $fresh_antechamber ]] || fail_test 'expected the fresh antechamber to be absent before --request-path'
FAMILIAR_HOME="$fresh_home"
fresh_request=$(run_config --request-path --name fresh-antechamber)
FAMILIAR_HOME=''
assert_equals "$fresh_request" "$fresh_antechamber/fresh-antechamber.md"
[[ -d $fresh_antechamber ]] || fail_test 'expected --request-path to create the antechamber directory'

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
default_launch_output=$(run_launcher --name "$default_name" --cwd "$work_directory" --harness codex)
default_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
expected_prompt="Read and follow the request at $default_timestamped_request. The resolved response path is $default_response. Work only within its stated scope. Do not create $default_response until the result is complete; then write the complete result there in a single write and state completion in this Familiar session. You may delegate read-only work (research, reading, checks) to headless sub-agents (cheaper models are fine), but make every file change yourself."
assert_contains "$default_command" 'exec codex --no-alt-screen'
assert_not_contains "$default_command" '--approve-for-me'
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
run_launcher --name "$codex_name" --cwd "$work_directory" --harness codex --model gpt-5.6-luna --effort high >/dev/null
codex_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$codex_command" "--model $(shell_quote gpt-5.6-luna)"
assert_contains "$codex_command" "--config $(shell_quote 'model_reasoning_effort=high')"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_harness\tcodex'

claude_name='claude-model-selection'
create_request "$claude_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
run_launcher --name "$claude_name" --cwd "$work_directory" --harness claude --model sonnet --effort ultra >/dev/null
claude_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$claude_command" 'CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1'
assert_contains "$claude_command" 'exec claude'
assert_not_contains "$claude_command" '--permission-mode'
assert_contains "$claude_command" "--name $(shell_quote "$TIMESTAMP-fm-$claude_name")"
assert_contains "$claude_command" "--model $(shell_quote sonnet)"
assert_contains "$claude_command" "--effort $(shell_quote ultra)"
assert_not_contains "$claude_command" 'codex'
assert_not_contains "$claude_command" '--approve-for-me'
assert_not_contains "$claude_command" '--no-alt-screen'
assert_not_contains "$claude_command" '--cd'
assert_not_contains "$claude_command" '--config'
assert_not_contains "$claude_command" 'model_reasoning_effort'
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_name\t'"$claude_name"
assert_file_contains "$FAKE_TMUX_OPTIONS" $'@familiar_timestamp\t'"$TIMESTAMP"

opencode_name='opencode-model-selection'
create_request "$opencode_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
run_launcher --name "$opencode_name" --cwd "$work_directory" --harness opencode --model provider/model >/dev/null
opencode_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$opencode_command" 'exec opencode'
assert_contains "$opencode_command" "--model $(shell_quote provider/model)"
assert_contains "$opencode_command" '--prompt '
assert_contains "$opencode_command" "$TIMESTAMP-fmrs-$opencode_name.md"
assert_not_contains "$opencode_command" '--auto'
assert_not_contains "$opencode_command" '--effort'

antigravity_name='antigravity-model-selection'
create_request "$antigravity_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
run_launcher --name "$antigravity_name" --cwd "$work_directory" --harness antigravity --model gemini-pro --effort high >/dev/null
antigravity_command=$(tail -n 1 "$FAKE_TMUX_SPLIT_ARGS")
assert_contains "$antigravity_command" 'exec agy'
assert_contains "$antigravity_command" "--model $(shell_quote gemini-pro)"
assert_contains "$antigravity_command" "--effort $(shell_quote high)"
assert_contains "$antigravity_command" '--prompt-interactive '
assert_contains "$antigravity_command" "$TIMESTAMP-fmrs-$antigravity_name.md"
assert_not_contains "$antigravity_command" '--dangerously-skip-permissions'

# Invalid input and launch failures must not consume the staged request.
for default_option in model effort; do
  reset_fake_tmux
  explicit_default_output=''
  if explicit_default_output=$(run_launcher \
    --name "explicit-default-$default_option" \
    --cwd "$work_directory" \
    --harness codex \
    "--$default_option" default 2>&1); then
    fail_test "expected explicit --$default_option default to fail"
  fi
  assert_contains "$explicit_default_output" "Omit --$default_option to use the harness-configured default."
  assert_no_split
done

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
  if run_launcher --name "$invalid_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
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
if run_launcher --name 'absent-harness' --cwd "$work_directory" >/dev/null 2>&1; then
  fail_test 'expected an omitted --harness to fail'
fi
assert_no_split

other_summoner_name='other-summoner-allowed'
create_request "$other_summoner_name" "$DEFAULT_STORAGE" >/dev/null
reset_fake_tmux
write_pane '%2' '1' 'other-summoner-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%99' '0'
run_launcher --name "$other_summoner_name" --cwd "$work_directory" --harness codex >/dev/null
assert_file_contains "$FAKE_TMUX_CALLS" 'split-window'

guard_name='guarded-launch'
guard_request=$(create_request "$guard_name" "$DEFAULT_STORAGE")
reset_fake_tmux
write_pane '%2' '1' 'existing-familiar' "$TIMESTAMP" codex "$DEFAULT_STORAGE" '%1' '0'
if run_launcher --name "$guard_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
  fail_test 'expected an existing managed Familiar to block the launch'
fi
assert_no_split
[[ -f $guard_request ]] || fail_test 'expected a blocked launch to preserve the staged request'

collision_name='durable-collision'
collision_request=$(create_request "$collision_name" "$DEFAULT_STORAGE")
touch -- "$DEFAULT_STORAGE/$TIMESTAMP-fmrq-$collision_name.md"
reset_fake_tmux
if run_launcher --name "$collision_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
  fail_test 'expected an existing durable request to block the launch'
fi
assert_no_split
[[ -f $collision_request ]] || fail_test 'expected a collision to preserve the staged request'

split_failure_name='split-failure'
split_failure_request=$(create_request "$split_failure_name" "$DEFAULT_STORAGE")
reset_fake_tmux
FAKE_TMUX_FAIL_COMMAND='split-window'
if run_launcher --name "$split_failure_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
  fail_test 'expected a split-window failure'
fi
FAKE_TMUX_FAIL_COMMAND=''
[[ -f $split_failure_request ]] || fail_test 'expected split failure to restore the staged request'
[[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-fmrq-$split_failure_name.md ]] || fail_test 'expected no durable request after split failure'

metadata_failure_name='metadata-failure'
metadata_failure_request=$(create_request "$metadata_failure_name" "$DEFAULT_STORAGE")
reset_fake_tmux
FAKE_TMUX_FAIL_SET_OPTION='@familiar_home'
if run_launcher --name "$metadata_failure_name" --cwd "$work_directory" --harness codex >/dev/null 2>&1; then
  fail_test 'expected a metadata failure'
fi
FAKE_TMUX_FAIL_SET_OPTION=''
[[ -f $metadata_failure_request ]] || fail_test 'expected metadata failure to restore the staged request'
[[ ! -e $DEFAULT_STORAGE/$TIMESTAMP-fmrq-$metadata_failure_name.md ]] || fail_test 'expected no durable request after metadata failure'
assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'

# Verify message delivery is scoped to the current summoning pane and sends text,
# waits 100 ms, then submits Enter in a separate tmux operation.
message_storage="$OVERRIDE_STORAGE"
FAMILIAR_HOME="$message_storage"
message_name='message-target'
message_request=$(create_request "$message_name" "$message_storage")
message_response=$(response_path_for "$message_name")
message_text='-follow-up text'
reset_fake_tmux
write_pane '%20' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
write_pane '%21' '1' 'other-summoner-message' "$TIMESTAMP" codex "$message_storage" '%99' '0'
write_pane '%22' '1' 'closed-message' "$TIMESTAMP" codex "$message_storage" '%1' '1'
message_state_before=$(<"$FAKE_TMUX_STATE")
message_output=$(run_message --message "$message_text")
assert_contains "$message_output" "Sent message to Familiar $message_name in pane %20."
expected_send_keys_args=$'send-keys\n-t\n%20\n-l\n--\n-follow-up text\nEND_CALL\nsend-keys\n-t\n%20\nC-m\nEND_CALL'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" "$expected_send_keys_args"
assert_equals "$(<"$FAKE_SLEEP_ARGS")" '0.1'
assert_equals "$(<"$FAKE_TMUX_CALLS")" $'list-panes\nsend-keys\nsleep\nsend-keys'
assert_equals "$(<"$FAKE_TMUX_STATE")" "$message_state_before"
[[ -f $message_request ]] || fail_test 'message delivery changed the request file'
[[ ! -e $message_response ]] || fail_test 'message delivery created the response file'

reset_fake_tmux
write_pane '%23' '1' 'closed-only' "$TIMESTAMP" codex "$message_storage" '%1' '1'
closed_output=''
if closed_output=$(run_message --message 'hello' 2>&1); then
  fail_test 'expected a message to fail when only closed Familiars exist'
fi
assert_contains "$closed_output" 'Only closed managed Familiars'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

reset_fake_tmux
no_familiar_output=''
if no_familiar_output=$(run_message --message 'hello' 2>&1); then
  fail_test 'expected a message to fail when no Familiar exists'
fi
assert_contains "$no_familiar_output" 'No managed Familiar'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

reset_fake_tmux
write_pane '%24' '1' 'first-live' "$TIMESTAMP" codex "$message_storage" '%1' '0'
write_pane '%25' '1' 'second-live' "$TIMESTAMP" codex "$message_storage" '%1' '0'
multiple_output=''
if multiple_output=$(run_message --message 'hello' 2>&1); then
  fail_test 'expected a message to fail when multiple live Familiars exist'
fi
assert_contains "$multiple_output" 'Multiple live managed Familiars'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_ARGS")" ''

reset_fake_tmux
write_pane '%26' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
FAKE_TMUX_FAIL_SEND_KEYS='1'
first_send_failure_output=''
if first_send_failure_output=$(run_message --message 'hello' 2>&1); then
  fail_test 'expected the message to fail when text delivery fails'
fi
FAKE_TMUX_FAIL_SEND_KEYS=''
assert_contains "$first_send_failure_output" 'Could not deliver the message'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_COUNT")" '1'

reset_fake_tmux
write_pane '%27' '1' "$message_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
FAKE_TMUX_FAIL_SEND_KEYS='2'
enter_failure_output=''
if enter_failure_output=$(run_message --message 'hello' 2>&1); then
  fail_test 'expected the message to fail when Enter delivery fails'
fi
FAKE_TMUX_FAIL_SEND_KEYS=''
assert_contains "$enter_failure_output" 'the message may remain unsubmitted'
assert_equals "$(<"$FAKE_TMUX_SEND_KEYS_COUNT")" '2'

# Verify dismissal resolves only the current summoner's live Familiar and never
# accepts an arbitrary pane target.
dismiss_name='dismiss-target'
reset_fake_tmux
write_pane '%28' '1' "$dismiss_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
write_pane '%29' '1' 'other-summoner-dismiss' "$TIMESTAMP" codex "$message_storage" '%99' '0'
dismiss_output=$(run_dismiss)
assert_contains "$dismiss_output" "Dismissed Familiar $dismiss_name in pane %28."
assert_file_contains "$FAKE_TMUX_CALLS" 'kill-pane'
assert_not_contains "$(<"$FAKE_TMUX_STATE")" '%28'
assert_file_contains "$FAKE_TMUX_STATE" '%29'

reset_fake_tmux
write_pane '%30' '1' "$dismiss_name" "$TIMESTAMP" codex "$message_storage" '%1' '0'
dismiss_state_before=$(<"$FAKE_TMUX_STATE")
arbitrary_target_output=''
if arbitrary_target_output=$(run_dismiss '%99' 2>&1); then
  fail_test 'expected dismissal with an arbitrary pane target to fail'
fi
assert_contains "$arbitrary_target_output" 'Unknown option: %99'
assert_equals "$(<"$FAKE_TMUX_STATE")" "$dismiss_state_before"
assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

reset_fake_tmux
no_familiar_output=''
if no_familiar_output=$(run_dismiss 2>&1); then
  fail_test 'expected dismissal to fail when no Familiar exists'
fi
assert_contains "$no_familiar_output" 'No managed Familiar'
assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

reset_fake_tmux
write_pane '%31' '1' 'closed-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '1'
closed_dismiss_output=''
if closed_dismiss_output=$(run_dismiss 2>&1); then
  fail_test 'expected dismissal to fail when only closed Familiars exist'
fi
assert_contains "$closed_dismiss_output" 'Only closed managed Familiars'
assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

reset_fake_tmux
write_pane '%32' '1' 'first-live-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '0'
write_pane '%33' '1' 'second-live-dismiss' "$TIMESTAMP" codex "$message_storage" '%1' '0'
multiple_dismiss_output=''
if multiple_dismiss_output=$(run_dismiss 2>&1); then
  fail_test 'expected dismissal to fail when multiple live Familiars exist'
fi
assert_contains "$multiple_dismiss_output" 'Multiple live managed Familiars'
assert_file_not_contains "$FAKE_TMUX_CALLS" 'kill-pane'

dismiss_help_output=$(run_dismiss --help 2>&1)
assert_contains "$dismiss_help_output" 'Usage: dismiss.sh'

message_help_output=$(run_message --help 2>&1)
assert_contains "$message_help_output" 'Usage: message.sh --message <text>'
for invalid_message_arguments in \
  '' \
  '--message' \
  '--message one --message two' \
  '--message one extra' \
  '--unknown'; do
  if [[ -z $invalid_message_arguments ]]; then
    read -r -a invalid_message_argv <<< ''
  else
    read -r -a invalid_message_argv <<< "$invalid_message_arguments"
  fi
  if run_message "${invalid_message_argv[@]}" >/dev/null 2>&1; then
    fail_test "expected invalid message arguments to fail: $invalid_message_arguments"
  fi
done

tmux_validation_output=''
if tmux_validation_output=$(env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$TEST_HOME" \
  FAMILIAR_HOME="$message_storage" \
  TMUX='' \
  TMUX_PANE='%1' \
  "$MESSAGE" --message hello 2>&1); then
  fail_test 'expected message delivery outside tmux to fail'
fi
assert_contains "$tmux_validation_output" 'must run inside tmux'

tmux_validation_output=''
if tmux_validation_output=$(env \
  PATH="$FAKE_BIN:$PATH" \
  HOME="$TEST_HOME" \
  FAMILIAR_HOME="$message_storage" \
  TMUX=1 \
  TMUX_PANE='' \
  "$MESSAGE" --message hello 2>&1); then
  fail_test 'expected message delivery without a tmux pane to fail'
fi
assert_contains "$tmux_validation_output" 'must run from a tmux pane'

# Verify reporting, waiting, and auto-close states across managed panes.
status_storage="$OVERRIDE_STORAGE"
FAMILIAR_HOME="$status_storage"
delivered_name='status-delivered'
awaiting_name='status-awaiting'
invalid_name='status-invalid'
dead_name='status-dead'
historical_name='historical-status'
historical_timestamp='250101-1234'
legacy_name='legacy-status'
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
write_pane '%10' '1' "$legacy_name" "$TIMESTAMP" '' "$status_storage" '%1' '0'
write_pane '%15' '1' 'other-summoner' "$TIMESTAMP" codex "$status_storage" '%99' '0'
FAMILIAR_HOME=''
status_output=$(run_status)
assert_contains "$status_output" 'Managed Familiar: status-delivered (codex, pane %4, response delivered)'
assert_contains "$status_output" 'Managed Familiar: status-awaiting (claude, pane %5, awaiting response)'
assert_contains "$status_output" 'Managed Familiar: status-invalid (claude, pane %7, response path invalid)'
assert_contains "$status_output" 'Managed Familiar: status-dead (codex, pane %8, ended without response)'
assert_contains "$status_output" 'Managed Familiar: legacy-status (unknown, pane %10, awaiting response)'
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
