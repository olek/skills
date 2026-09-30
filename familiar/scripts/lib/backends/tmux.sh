#!/usr/bin/env bash
# Implement Familiar's backend contract with tmux panes and pane options.

readonly FAMILIAR_TMUX_OPTION='@familiar'
readonly FAMILIAR_TMUX_NAME_OPTION='@familiar_name'
readonly FAMILIAR_TMUX_TIMESTAMP_OPTION='@familiar_timestamp'
readonly FAMILIAR_TMUX_HARNESS_OPTION='@familiar_harness'
readonly FAMILIAR_TMUX_HOME_OPTION='@familiar_home'
readonly FAMILIAR_TMUX_SUMMONER_OPTION='@familiar_summoner_pane'

familiar_backend_require_context() {
  [[ -n ${TMUX:-} ]] || {
    printf 'This command must run inside tmux.\n' >&2
    return 1
  }
  [[ -n ${TMUX_PANE:-} ]] || {
    printf 'This command must run from a tmux pane.\n' >&2
    return 1
  }
}

familiar_backend_summoner_id() {
  printf '%s\n' "$TMUX_PANE"
}

familiar_backend_can_launch() {
  local -r summoner_id=$1
  if familiar_backend_list_familiars "$summoner_id" | awk 'NF { found = 1 } END { exit found ? 0 : 1 }'; then
    printf 'This summoning agent instance already has a managed Familiar; close it before summoning another.\n' >&2
    return 1
  fi
}

familiar_backend_display_noun() { printf 'pane'; }

familiar_backend_list_familiars() {
  local -r summoner_id=$1

  local format
  printf -v format '#{pane_id}\t#{%s}\t#{%s}\t#{%s}\t#{%s}\t#{%s}\t#{%s}\t#{pane_dead}' \
    "$FAMILIAR_TMUX_OPTION" "$FAMILIAR_TMUX_NAME_OPTION" "$FAMILIAR_TMUX_TIMESTAMP_OPTION" \
    "$FAMILIAR_TMUX_HARNESS_OPTION" "$FAMILIAR_TMUX_HOME_OPTION" "$FAMILIAR_TMUX_SUMMONER_OPTION"
  tmux list-panes -a -F "$format" \
    | awk -F '\t' -v summoner="$summoner_id" '
      $2 == "1" && $7 == summoner {
        harness = $5
        if (harness == "") {
          harness = "unknown"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $3, $4, harness, $6, $8
      }'
}

familiar_backend_launch_familiar() {
  local -r summoner_id=$1
  local -r working_directory=$2
  local -r command=$3
  local -r familiar_name=$4
  local -r familiar_timestamp=$5
  local -r harness=$6
  local -r home=$7
  local window_id
  local pane_id

  window_id=$(tmux display-message -p -t "$summoner_id" '#{window_id}') || return 1
  if ! pane_id=$(tmux split-window -h -c "$working_directory" -t "$window_id" -P -F '#{pane_id}' "$command"); then
    return 1
  fi
  local option value
  local -a metadata=(
    "$FAMILIAR_TMUX_NAME_OPTION" "$familiar_name"
    "$FAMILIAR_TMUX_TIMESTAMP_OPTION" "$familiar_timestamp"
    "$FAMILIAR_TMUX_HARNESS_OPTION" "$harness"
    "$FAMILIAR_TMUX_HOME_OPTION" "$home"
    "$FAMILIAR_TMUX_SUMMONER_OPTION" "$summoner_id"
    "$FAMILIAR_TMUX_OPTION" 1
  )
  while ((${#metadata[@]})); do
    option=${metadata[0]}
    value=${metadata[1]}
    if ! tmux set-option -p -t "$pane_id" "$option" "$value"; then
      tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true
      return 1
    fi
    metadata=("${metadata[@]:2}")
  done
  printf '%s\n' "$pane_id"
}

familiar_backend_send_literal() {
  local -r familiar_id=$1
  local -r literal_text=$2

  tmux send-keys -t "$familiar_id" -l -- "$literal_text"
}

familiar_backend_submit() {
  local -r familiar_id=$1

  tmux send-keys -t "$familiar_id" C-m
}

familiar_backend_close_familiar() {
  local -r familiar_id=$1

  tmux kill-pane -t "$familiar_id"
}
