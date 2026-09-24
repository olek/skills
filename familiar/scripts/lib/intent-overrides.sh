#!/usr/bin/env bash
# Read user-owned Familiar model and effort overrides without executing them.

familiar_intent_override_pair() {
  local -r requested_harness=$1
  local -r requested_intent=$2
  local override_file
  local line
  local line_number=0
  local key
  local separator
  local model
  local effort
  local extra
  local found=0
  local pair=''

  override_file=$(familiar_intent_overrides_path) || return 2
  readonly override_file
  [[ -e $override_file ]] || return 1
  [[ -f $override_file && -r $override_file ]] || {
    printf 'Familiar intent overrides path is not a readable file: %s\n' "$override_file" >&2
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
      printf 'Invalid Familiar intent override at %s:%d; expected <harness>.<intent> = <model> <effort>\n' "$override_file" "$line_number" >&2
      return 2
    fi
    if [[ $key == "$requested_harness.$requested_intent" ]]; then
      (( found == 0 )) || {
        printf 'Duplicate Familiar intent override for %s at %s:%d\n' "$key" "$override_file" "$line_number" >&2
        return 2
      }
      pair="$model $effort"
      found=1
    fi
  done < "$override_file"

  (( found )) || return 1
  printf '%s\n' "$pair"
}
