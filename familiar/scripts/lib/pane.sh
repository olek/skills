#!/usr/bin/env bash
# Shared lookup and close operations for panes managed by Familiar.

familiar_managed_rows() {
  local -r summoner_pane=$1

  # Each row contains pane ID, name, timestamp, harness, home, and dead flag.
  # A pane with no recorded harness is reported as "unknown"; the launcher
  # always records one, so this only guards against missing metadata.
  tmux list-panes -a -F $'#{pane_id}\t#{@familiar}\t#{@familiar_name}\t#{@familiar_timestamp}\t#{@familiar_harness}\t#{@familiar_home}\t#{@familiar_summoner_pane}\t#{pane_dead}' \
    | awk -F '\t' -v summoner="$summoner_pane" '
      $2 == "1" && $7 == summoner {
        harness = $5
        if (harness == "") {
          harness = "unknown"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $3, $4, harness, $6, $8
      }'
}

familiar_resolve_live_familiar() {
  local -n familiar_name_ref=$1
  local -n pane_id_ref=$2
  local -r summoner_pane=$3
  local candidate_pane_id
  local candidate_familiar_name
  local candidate_pane_dead
  local live_count=0
  local managed_count=0

  while IFS=$'\t' read -r candidate_pane_id candidate_familiar_name _ _ _ candidate_pane_dead; do
    [[ -n $candidate_pane_id ]] || continue
    managed_count=$((managed_count + 1))
    if [[ $candidate_pane_dead == 0 ]]; then
      live_count=$((live_count + 1))
      # shellcheck disable=SC2034 # These namerefs return the selected Familiar to the caller.
      familiar_name_ref=$candidate_familiar_name
      # shellcheck disable=SC2034 # These namerefs return the selected pane to the caller.
      pane_id_ref=$candidate_pane_id
    fi
  done < <(familiar_managed_rows "$summoner_pane")

  if (( ! managed_count )); then
    printf 'No managed Familiar is associated with summoning pane %s.\n' "$summoner_pane" >&2
    return 1
  fi
  if (( ! live_count )); then
    printf 'Only closed managed Familiars are associated with summoning pane %s.\n' "$summoner_pane" >&2
    return 1
  fi
  if (( live_count != 1 )); then
    printf 'Multiple live managed Familiars are associated with summoning pane %s.\n' "$summoner_pane" >&2
    return 1
  fi
}

familiar_close_pane() {
  local -r pane_id=$1

  tmux kill-pane -t "$pane_id"
}
