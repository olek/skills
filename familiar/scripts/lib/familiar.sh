#!/usr/bin/env bash
# Apply transport-neutral policy to Familiars managed by one summoner.

familiar_managed_familiars() {
  # Each normalized record is: familiar_id, name, timestamp, harness, home, closed.
  familiar_backend_list_familiars "$1"
}

familiar_resolve_live_familiar() {
  local -n familiar_name_ref=$1
  local -n familiar_id_ref=$2
  local -r summoner_id=$3
  local candidate_familiar_id
  local candidate_familiar_name
  local candidate_closed
  local live_count=0
  local managed_count=0

  while IFS=$'\t' read -r candidate_familiar_id candidate_familiar_name _ _ _ candidate_closed; do
    [[ -n $candidate_familiar_id ]] || continue
    managed_count=$((managed_count + 1))
    if [[ $candidate_closed == 0 ]]; then
      live_count=$((live_count + 1))
      # shellcheck disable=SC2034 # This nameref returns the selected Familiar to the caller.
      familiar_name_ref=$candidate_familiar_name
      # shellcheck disable=SC2034 # This nameref returns the selected Familiar ID to the caller.
      familiar_id_ref=$candidate_familiar_id
    fi
  done < <(familiar_managed_familiars "$summoner_id")

  if (( ! managed_count )); then
    printf 'No managed Familiar is associated with summoner %s.\n' "$summoner_id" >&2
    return 1
  fi
  if (( ! live_count )); then
    printf 'Only closed managed Familiars are associated with summoner %s.\n' "$summoner_id" >&2
    return 1
  fi
  if (( live_count != 1 )); then
    printf 'Multiple live managed Familiars are associated with summoner %s.\n' "$summoner_id" >&2
    return 1
  fi
}

familiar_close_familiar() {
  familiar_backend_close_familiar "$1"
}

familiar_display_noun() {
  if declare -F familiar_backend_display_noun >/dev/null; then
    familiar_backend_display_noun
  else
    printf 'pane'
  fi
}
