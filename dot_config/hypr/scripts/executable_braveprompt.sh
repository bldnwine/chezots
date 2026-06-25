#!/usr/bin/env bash

HISTORY_DB="$HOME/.config/BraveSoftware/Brave-Browser/Default/History"
TEMP_DB="/tmp/brave_history_$$.db"

# 1. Fetch History
if [ -f "$HISTORY_DB" ]; then
  cp "$HISTORY_DB" "$TEMP_DB"
  TARGET=$(sqlite3 "$TEMP_DB" "SELECT url FROM urls ORDER BY visit_count DESC LIMIT 1000;" 2>/dev/null | rofi -dmenu -i -p "Brave Go:")
  rm -f "$TEMP_DB"
else
  TARGET=$(rofi -dmenu -p "Brave Go:")
fi

[[ -z "$TARGET" ]] && exit 0

# 2. Route Input
# Check 1: Explicit protocols
if [[ "$TARGET" =~ ^(https?|brave|chrome|file):// ]]; then
  brave "$TARGET" &

# Check 2: Custom Bangs
elif [[ "$TARGET" =~ ^!([a-zA-Z0-9]+)[[:space:]]+(.*)$ ]]; then
  BANG="${BASH_REMATCH[1]}"
  QUERY="${BASH_REMATCH[2]}"
  ENCODED_QUERY=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$QUERY")

  case "$BANG" in
  br) brave "https://search.brave.com/search?q=$ENCODED_QUERY" & ;;
  yt) brave "https://www.youtube.com/results?search_query=$ENCODED_QUERY" & ;;
  ym) brave "https://music.youtube.com/search?q=$ENCODED_QUERY" & ;;
  per) brave "https://www.perplexity.ai/?q=$ENCODED_QUERY" & ;;
  *) # Fallback if bang is unregistered: search literal string on Google
    ENCODED_TARGET=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TARGET")
    brave "https://www.google.com/search?q=$ENCODED_TARGET" &
    ;;
  esac

# Check 3: Standard domains
elif [[ "$TARGET" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,6}(/.*)?$ && ! "$TARGET" =~ [[:space:]] ]]; then
  brave "$TARGET" &

# Check 4: Standard Google Search fallback
else
  ENCODED_TARGET=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TARGET")
  brave "https://www.google.com/search?q=$ENCODED_TARGET" &
fi
