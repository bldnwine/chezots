#!/usr/bin/env bash

CHIST="/usr/bin/cliphist"
TOFI="/usr/bin/tofi"
WLCOPY="/usr/bin/wl-copy"

tofi_input() {
  local prompt="$1"
  echo -n "" | $TOFI --prompt-text "$prompt" --width 30% --height 5% --require-match false
}

exec_delete() {
  local arg="$1"

  if [[ -z "$arg" ]]; then
    arg=$(tofi_input "Enter count or ID to delete:")
    [[ -z "$arg" ]] && return
  fi

  if [[ "$arg" =~ ^last\ +([0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    $CHIST list | head -n "$n" | $CHIST delete
    return
  fi

  [[ ! "$arg" =~ ^[0-9]+$ ]] && return

  # Check if arg is a known ID; if so delete by ID, else delete last N
  if $CHIST list | cut -f1 | grep -qx "$arg"; then
    echo "$arg" | $CHIST delete
  else
    $CHIST list | head -n "$arg" | $CHIST delete
  fi
}

handle_cmd() {
  local raw="$1"
  local cmd="${raw#!}"

  case "$cmd" in
  clearclip | wipe | clear)
    $CHIST wipe
    return 0
    ;;
  del\ *)
    local arg="${cmd#del }"
    arg=$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$arg")
    exec_delete "$arg"
    return 0
    ;;
  del)
    exec_delete ""
    return 0
    ;;
  esac
  return 1
}

selection=$(
  $CHIST list | sed $'s/\t/ - /' | $TOFI \
    \
    --anchor center \
    --width 40% \
    --height 30% \
    --require-match false # --prompt-text "Clipboard History" \
)

[[ -z "$selection" ]] && exit 0

handle_cmd "$selection" && exit 0

item_id="${selection%% - *}"
$CHIST decode "$item_id" | $WLCOPY
