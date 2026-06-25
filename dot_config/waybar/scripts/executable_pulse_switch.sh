#!/usr/bin/env bash
set -euo pipefail

# Get current default sink
current=$(pactl get-default-sink 2>/dev/null || echo "")

# Get all sinks
mapfile -t sinks < <(
  pactl list sinks | awk '/Name: / {print $2}'
)

# Need at least 2 sinks to cycle
(( ${#sinks[@]} > 1 )) || exit 0

# Find next sink
idx=0
for i in "${!sinks[@]}"; do
  [[ "${sinks[i]}" == "$current" ]] && idx=$i && break
done
next="${sinks[$(( (idx + 1) % ${#sinks[@]} ))]}"

# Set new default and move all inputs
pactl set-default-sink "$next"
pactl list short sink-inputs | awk '{print $1}' | while read -r id; do
  pactl move-sink-input "$id" "$next" 2>/dev/null || true
done
