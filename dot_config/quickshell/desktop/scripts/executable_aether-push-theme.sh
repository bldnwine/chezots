#!/bin/bash
set -euo pipefail

COLORS_FILE="$HOME/.config/aether/theme/colors.toml"
[ -f "$COLORS_FILE" ] || exit 0

JSON=$(awk -F '=' '
  /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*"/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
    val = $2
    gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", val)
    gsub(/[[:space:]]*$/, "", val)
    gsub(/"/, "\\\"", val)
    keys[++n] = $1
    vals[$1] = val
  }
  END {
    printf "{"
    for (i = 1; i <= n; i++) {
      if (i > 1) printf ","
      printf "\"%s\":\"%s\"", keys[i], vals[keys[i]]
    }
    printf "}"
  }
' "$COLORS_FILE")

exec qs -c desktop ipc call theme apply "{\"colors\":$JSON}"
