#!/usr/bin/env bash
set -euo pipefail

# Cycle audio outputs as sink:port pairs (ports included, e.g. speaker/headphones).
mapfile -t outs < <(
  pactl list sinks | awk '
    /^Sink #/ { sink=""; active="" }
    /^\tName: / { sink=$2 }
    /^\tActive Port: / { active=$3 }
    /^\tPorts:/ { inports=1; next }
    inports && /^\t\t[^:]*(:)/ { port=$1; gsub(":","",port); print sink ":" port }
    inports && !/^\t\t/ { inports=0 }
  '
)

(( ${#outs[@]} > 1 )) || exit 0

current=$(pactl get-default-sink)
current+=":$(pactl list sinks | awk -v s="$current" '$0 ~ "^\\tName: " s {found=1} found && /^\tActive Port: / {print $3; exit}')"

idx=0
for i in "${!outs[@]}"; do
  [[ "${outs[i]}" == "$current" ]] && idx=$i && break
done
next="${outs[$(( (idx + 1) % ${#outs[@]} ))]}"

sink="${next%%:*}"
port="${next##*:}"

pactl set-default-sink "$sink"
pactl set-sink-port "$sink" "$port"
pactl list short sink-inputs | awk '{print $1}' | xargs -r -I{} pactl move-sink-input {} "$sink"
qs -c desktop ipc call audio refresh >/dev/null 2>&1 || true
