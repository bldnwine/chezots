#!/bin/bash

options="Shutdown\nReboot\nSuspend\nLogout"

#selected=$(echo -e "$options" | tofi --prompt-text "Power: ")
selected=$(echo -e "$options" | tofi \
  --prompt-text "" \
  --width 150 \
  --height 217 \
  --num-results 4 \
  --selection-color "#d1c464" \
  --outline-width 1 \
  --outline-color "#c0caf5" \
  --corner-radius 15 \
  --padding-left 15 \
  --padding-top 10 \
  --result-spacing 15 \
  --anchor center)

case $selected in
Shutdown)
  systemctl poweroff
  ;;
Reboot)
  systemctl reboot
  ;;
Suspend)
  systemctl suspend
  ;;
Logout)
  hyprctl dispatch exit
  ;;
esac
