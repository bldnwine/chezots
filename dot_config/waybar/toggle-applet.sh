#!/bin/bash
# ~/.config/waybar/toggle-applet.sh

# Example: toggle a simple eww window
if pgrep -f "eww daemon" > /dev/null; then
    if eww get applet_open 2>/dev/null | grep -q true; then
        eww update applet_open=false
        eww close applet
    else
        eww update applet_open=true
        eww open applet
    fi
else
    eww daemon
    eww open applet
fi

