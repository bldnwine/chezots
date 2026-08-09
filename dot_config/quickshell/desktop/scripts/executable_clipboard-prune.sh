#!/bin/bash
# One-shot orphan/temp cleanup for the clipboard manager. Runs at qs startup:
# removes image files no longer referenced by history (eviction/crash leftovers)
# and clipboard-open temp files older than a day. No-op when there's nothing.
set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-desktop"
HIST="$STATE_DIR/clipboard-history.json"
IMAGE_DIR="$STATE_DIR/clipboard-images"
TEMP_DIR="$STATE_DIR/clipboard-open"

[[ -d $TEMP_DIR ]] && find "$TEMP_DIR" -type f -mtime +1 -delete

[[ -d $IMAGE_DIR && -f $HIST ]] || exit 0
refs=$(jq -r '.[] | select(.type=="image") | .path' "$HIST" 2>/dev/null || true)
find "$IMAGE_DIR" -maxdepth 1 -type f -printf '%f\n' | while IFS= read -r name; do
    [[ "$refs" == *"$IMAGE_DIR/$name"* ]] && continue
    rm -f "$IMAGE_DIR/$name"
done