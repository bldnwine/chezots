#!/usr/bin/env bash

current=$(hyprctl getoption general:layout -j | jq -r '.str')

layout=$(echo -e "scrolling\ndwindle\nmaster\nmonocle" | rofi -dmenu -p "Layout" -selected-row $(echo -e "scrolling\ndwindle\nmaster\nmonocle" | grep -n "^${current}$" | cut -d: -f1 | head -1))

[ -z "$layout" ] && exit 0

hyprctl eval "hl.config({ general = { layout = '$layout' } })"
