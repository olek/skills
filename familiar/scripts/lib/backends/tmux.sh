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

familiar_backend_list_familiars() {
  local -r summoner_id=$1

  tmux list-panes -a -F $'#{pane_id}\t#{@familiar}\t#{@familiar_name}\t#{@familiar_timestamp}\t#{@familiar_harness}\t#{@familiar_home}\t#{@familiar_summoner_pane}\t#{pane_dead}' \
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
  local -r storage_directory=$7
  local window_id
  local pane_id

  window_id=$(tmux display-message -p -t "$summoner_id" '#{window_id}') || return 1
  if ! pane_id=$(tmux split-window -h -c "$working_directory" -t "$window_id" -P -F '#{pane_id}' "$command"); then
    return 1
  fi
  if ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_NAME_OPTION" "$familiar_name" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_TIMESTAMP_OPTION" "$familiar_timestamp" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_HARNESS_OPTION" "$harness" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_HOME_OPTION" "$storage_directory" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_SUMMONER_OPTION" "$summoner_id" \
    || ! tmux set-option -p -t "$pane_id" "$FAMILIAR_TMUX_OPTION" 1; then
    tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    return 1
  fi
  printf '%s\n' "$pane_id"
}

familiar_backend_send_literal() {
  local -r familiar_id=$1
  local -r literal_text=$2
  local -r pane_id=$familiar_id

  tmux send-keys -t "$pane_id" -l -- "$literal_text"
}

familiar_backend_submit() {
  local -r familiar_id=$1
  local -r pane_id=$familiar_id

  tmux send-keys -t "$pane_id" C-m
}

familiar_backend_close_familiar() {
  local -r familiar_id=$1
  local -r pane_id=$familiar_id

  tmux kill-pane -t "$pane_id"
}
