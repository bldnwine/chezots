#!/usr/bin/env bash

# Define options
options="󰌾 Lock\n󰤄 Suspend\n󰐥 Shutdown\n󰜉 Reboot\n󰗽 Logout\n󰒲 Hibernate"

# Use Tofi to pick one
chosen=$(echo -e "$options" | tofi \
  --config ~/.config/aether/theme/tofi-config \
  --prompt-text="" \
  --width=150 \
  --height=220 \
  --num-results=6)

# Action logic
case $chosen in
*Lock) loginctl lock-session ;;
*Suspend) systemctl suspend ;;
*Shutdown) systemctl poweroff ;;
*Reboot) systemctl reboot ;;
*Logout) uwsm stop ;;
*Hibernate) systemctl hibernate ;;
esac
