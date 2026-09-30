#!/usr/bin/env bash
# Read user-owned Familiar model and effort choices without executing them.

familiar_intent_config_pair() {
  local -r requested_harness=$1
  local -r requested_intent=$2
  local config_file
  local line
  local line_number=0
  local key
  local separator
  local model
  local effort
  local extra
  local found=0
  local pair=''

  config_file=$(familiar_intent_config_path) || return 2
  readonly config_file
  [[ -e $config_file ]] || return 1
  [[ -f $config_file && -r $config_file ]] || {
    printf 'Familiar intent configuration is not a readable file: %s\n' "$config_file" >&2
    return 2
  }

  while IFS= read -r line || [[ -n $line ]]; do
    line_number=$((line_number + 1))
    line=${line%%#*}
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    key=''
    separator=''
    model=''
    effort=''
    extra=''
    read -r key separator model effort extra <<< "$line"
    if [[ ! $key =~ ^[a-z0-9][a-z0-9-]*\.(planning|implementation|review)$ || $separator != '=' || -z $model || -z $effort || -n $extra ]]; then
      printf 'Invalid Familiar intent entry at %s:%d; expected <harness>.<intent> = <model> <effort>\n' "$config_file" "$line_number" >&2
      return 2
    fi
    if ! familiar_harness_is_known "${key%%.*}"; then
      printf 'Unknown Familiar harness in intent configuration at %s:%d: %s\n' "$config_file" "$line_number" "${key%%.*}" >&2
      return 2
    fi
    if [[ $key == "$requested_harness.$requested_intent" ]]; then
      (( found == 0 )) || {
        printf 'Duplicate Familiar intent entry for %s at %s:%d\n' "$key" "$config_file" "$line_number" >&2
        return 2
      }
      pair="$model $effort"
      found=1
    fi
  done < "$config_file"

  (( found )) || return 1
  printf '%s\n' "$pair"
}
