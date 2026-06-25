#!/usr/bin/env bash

# Define options
options="󰐥 Shutdown\n󰜉 Reboot\n󰤄 Suspend\n󰗽 Logout\n󰒲 Hibernate"

# Use Tofi to pick one
chosen=$(echo -e "$options" | tofi --prompt-text "Power: " --num-results 5)

# Action logic
case $chosen in
    *Shutdown) systemctl poweroff ;;
    *Reboot) systemctl reboot ;;
    *Suspend) systemctl suspend ;;
    *Logout) hyprctl dispatch exit ;;
    *Hibernate) systemctl hibernate ;;
esac
