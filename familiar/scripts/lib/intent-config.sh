#!/usr/bin/env bash
# Read user-owned Familiar model and effort choices without executing them.
# Source paths.sh and harness.sh first.
# shellcheck disable=SC2034 # Sourced by defaults.sh.
FAMILIAR_INTENTS=(planning implementation review)

familiar_intent_config_entries() {
  local -r requested_harness=$1
  local config_file line key separator model effort extra
  local line_number=0
  local -A seen=()

  config_file=$(familiar_intent_config_path) || return 2
  [[ -e $config_file ]] || return 1
  [[ -f $config_file && -r $config_file ]] || {
    printf 'Familiar intent configuration is not a readable file: %s\n' "$config_file" >&2
    return 2
  }
  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    line=${line%%#*}
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    read -r key separator model effort extra <<< "$line"
    if [[ ! $key =~ ^[a-z0-9][a-z0-9-]*\.[a-z]+$ || " ${FAMILIAR_INTENTS[*]} " != *" ${key#*.} "* || $separator != '=' || -z $model || -z $effort || -n $extra ]]; then
      printf 'Invalid Familiar intent entry at %s:%d; expected <harness>.<intent> = <model> <effort>\n' "$config_file" "$line_number" >&2
      return 2
    fi
    if ! familiar_harness_is_known "${key%%.*}"; then
      printf 'Unknown Familiar harness in intent configuration at %s:%d: %s\n' "$config_file" "$line_number" "${key%%.*}" >&2
      return 2
    fi
    if [[ ${seen[$key]:-} ]]; then
      printf 'Duplicate Familiar intent entry for %s at %s:%d\n' "$key" "$config_file" "$line_number" >&2
      return 2
    fi
    seen[$key]=1
    if [[ ${key%%.*} == "$requested_harness" ]]; then
      printf '%s\t%s\t%s\n' "${key#*.}" "$model" "$effort"
    fi
  done < "$config_file"
}
