#!/usr/bin/env bash

get_active_interface() {
  ls /sys/class/net/ 2>/dev/null | grep '^proton' | head -n 1
}

case "$1" in
--status)
  ACTIVE_IFACE=$(get_active_interface)
  if [ -n "$ACTIVE_IFACE" ]; then
    echo "{\"text\": \"$ACTIVE_IFACE\", \"alt\": \"connected\", \"tooltip\": \"Connected to $ACTIVE_IFACE\", \"class\": \"connected\"}"
  else
    echo "{\"text\": \"\"}"
  fi
  ;;

--menu)
  ACTIVE_IFACE=$(get_active_interface)

  # Dynamically list filenames without reading file contents
  CONFIGS=$(sudo /usr/bin/ls /etc/wireguard 2>/dev/null | grep '^proton.*\.conf$' | sed 's/\.conf$//' | sort)

  if [ -z "$CONFIGS" ]; then
    rofi -e "No proton*.conf profiles found in /etc/wireguard/"
    exit 1
  fi

  MENU_OPTIONS=""
  if [ -n "$ACTIVE_IFACE" ]; then
    MENU_OPTIONS="🛑 Disconnect ($ACTIVE_IFACE)\n"
  fi

  for c in $CONFIGS; do
    if [ "$c" != "$ACTIVE_IFACE" ]; then
      MENU_OPTIONS+="🔒 Connect $c\n"
    fi
  done

  SELECTION=$(echo -e -n "$MENU_OPTIONS" | sed '/^$/d' | rofi -dmenu -i -p "Proton VPN" -theme-str 'window {width: 250px;} listview {lines: 6;}')

  if [ -z "$SELECTION" ]; then
    exit 0
  fi

  if [[ "$SELECTION" == 🛑* ]]; then
    sudo /usr/bin/wg-quick down "$ACTIVE_IFACE"
  elif [[ "$SELECTION" == 🔒* ]]; then
    TARGET_IFACE=$(echo "$SELECTION" | awk '{print $NF}')
    if [ -n "$ACTIVE_IFACE" ]; then
      sudo /usr/bin/wg-quick down "$ACTIVE_IFACE"
    fi
    sudo /usr/bin/wg-quick up "$TARGET_IFACE"
  fi

  pkill -SIGRTMIN+1 waybar
  ;;

*)
  echo "Usage: $0 [--status | --menu]"
  exit 1
  ;;
esac
