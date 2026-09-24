#!/usr/bin/env bash
# Verify Familiar paths, catalogs, lifecycle, messaging, dismissal, and status.
set -euo pipefail

SKILL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
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
readonly DEFAULT_SUMMONINGS="$DEFAULT_STORAGE/summonings"
readonly OVERRIDE_STORAGE="$TEST_ROOT/override familiar home"
readonly OVERRIDE_ANTECHAMBER="$OVERRIDE_STORAGE/antechamber"
readonly OVERRIDE_SUMMONINGS="$OVERRIDE_STORAGE/summonings"
TIMESTAMP=$(date +%y%m%d-%H%M)
readonly TIMESTAMP
FAMILIAR_HOME=''
	FAMILIAR_AUTO_DISMISS_SECONDS=''
	FAKE_TMUX_AUTO_DISMISS_ENABLED=0
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
	if (( FAKE_TMUX_AUTO_DISMISS_ENABLED )); then
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

assert_no_split() {
  local split_count
  split_count=$(awk '$1 == "split-window" { count++ } END { print count + 0 }' "$FAKE_TMUX_CALLS")
  readonly split_count
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
		FAKE_TMUX_AUTO_DISMISS_ENABLED="$FAKE_TMUX_AUTO_DISMISS_ENABLED" \
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
		FAMILIAR_AUTO_DISMISS_SECONDS="$FAMILIAR_AUTO_DISMISS_SECONDS" \
		FAKE_TMUX_AUTO_DISMISS_ENABLED="$FAKE_TMUX_AUTO_DISMISS_ENABLED" \
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
		FAKE_TMUX_AUTO_DISMISS_ENABLED="$FAKE_TMUX_AUTO_DISMISS_ENABLED" \
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
		FAKE_TMUX_AUTO_DISMISS_ENABLED="$FAKE_TMUX_AUTO_DISMISS_ENABLED" \
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
    HOME="$TEST_HOME" \
    FAMILIAR_HOME="$FAMILIAR_HOME" \
    "$DEFAULTS" "$@"
}

assert_default_pair_contract() {
	local -r harness=$1
		local -r intent=$2
		local output
		local -a lines
		local model
		local effort
		local catalog

		output=$(run_defaults --harness "$harness" --intent "$intent")
		mapfile -t lines <<< "$output"
		[[ ${#lines[@]} == 2 ]] || fail_test "expected one model and one effort for $harness $intent"
		[[ ${lines[0]} == model=?* ]] || fail_test "expected a non-empty model for $harness $intent"
			[[ ${lines[1]} == effort=?* ]] || fail_test "expected a non-empty effort for $harness $intent"

				model=${lines[0]#model=}
	effort=${lines[1]#effort=}
	if [[ $model != default ]]; then
		catalog=$(run_models --harness "$harness")
			grep -Fxq -- "$model" <<< "$catalog" || fail_test "expected model $model in the $harness model catalog"
			fi
			if [[ $effort != default ]]; then
				catalog=$(run_efforts --harness "$harness")
					grep -Fxq -- "$effort" <<< "$catalog" || fail_test "expected effort $effort in the $harness effort catalog"
					fi
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


write_pane() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$FAKE_TMUX_STATE"
}
