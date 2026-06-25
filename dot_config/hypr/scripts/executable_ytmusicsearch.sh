#!/usr/bin/env bash

# 1. Get user input via Rofi
query=$(echo "" | rofi -dmenu -p "YouTube Music " \
  -theme-str 'window {width: 500px; border: 0; border-color: #ffffff; background-color: #1e1e2e; border-radius: 15px;} mainbox {padding: 10px; children: [inputbar];} inputbar {children: [prompt, entry];} entry {placeholder: "Type to search..."; text-color: #ffffff;} prompt {text-color: #ff3344; margin: 0 10px 0 0;} listview {enabled: false;}')
# 2. Exit if the user hits ESC or enters nothing
if [ -z "$query" ]; then
  exit 0
fi

# 3. Find the App ID for "YouTube Music.desktop"
# We look for the line starting with Exec in your local desktop file
# Webapp desktop files usually look like: Exec=brave --app-id=abcdefg...
APP_ID=$(grep -Po '(?<=--app-id=)[^ ]*' "$HOME/.local/share/applications/YouTube Music.desktop" | head -1)

# 4. Format query for URL (spaces to +)
search_query=$(echo "$query" | tr ' ' '+')

# 5. Launch the WebApp directly into the search results page
if [ -n "$APP_ID" ]; then
  # Launching via app-id keeps it in the "standalone" window
  echo "DEBUG: Using APP_ID=$APP_ID with URL: https://music.youtube.com/$search?q=search_query" >&2
  brave --app-id="$APP_ID" --app-launch-url-for-shortcuts-menu-item="https://music.youtube.com/search?q=$search_query"
else
  # Fallback if the desktop file isn't found or has no ID
  echo "DEBUG: Using fallback URL: https://music.youtube.com/search?q=$search_query" >&2
  brave --app="https://music.youtube.com/search?q=$search_query"
fi
