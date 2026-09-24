test_familiar_lifecycle() {
  local generic_policy_output
  local generic_multiple_output

  generic_policy_output=$(FAKE_FAMILIAR_ROWS=$'familiar-1\tfake-familiar\tstamp\tcodex\thome\t0' bash -c '
    set -euo pipefail
    familiar_backend_list_familiars() { printf "%s\\n" "$FAKE_FAMILIAR_ROWS"; }
    familiar_backend_close_familiar() { printf "closed:%s\\n" "$1"; }
    source "$1"
    name=""; familiar=""
    familiar_resolve_live_familiar name familiar summoner
    printf "resolved:%s:%s\\n" "$name" "$familiar"
    familiar_close_familiar "$familiar"
  ' -- "$FAMILIAR_POLICY" 2>&1) || fail_test 'expected lifecycle resolution to succeed'
  assert_equals "$generic_policy_output" $'resolved:fake-familiar:familiar-1\nclosed:familiar-1'

  generic_multiple_output=''
  if generic_multiple_output=$(FAKE_FAMILIAR_ROWS=$'familiar-1\tfirst\tstamp\tcodex\thome\t0\nfamiliar-2\tsecond\tstamp\tcodex\thome\t0' bash -c '
    set -euo pipefail
    familiar_backend_list_familiars() { printf "%s\\n" "$FAKE_FAMILIAR_ROWS"; }
    source "$1"
    name=""; familiar=""
    familiar_resolve_live_familiar name familiar summoner
  ' -- "$FAMILIAR_POLICY" 2>&1); then
    fail_test 'expected lifecycle resolution to reject multiple Familiars'
  fi
  assert_contains "$generic_multiple_output" 'Multiple live managed Familiars are associated with summoner summoner.'
}
