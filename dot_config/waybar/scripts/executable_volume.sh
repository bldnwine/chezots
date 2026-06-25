#!/bin/bash
# Optimized Volume control script for Waybar with Hyprland
iDIR="$HOME/.config/waybar/icons"

# Get Volume and Mute Status in one go if possible, or cache them
get_status() {
    volume=$(pamixer --get-volume)
    is_muted=$(pamixer --get-mute)
}

# Get icons
get_icon() {
    local vol=$1
    local muted=$2
    if [[ "$muted" == "true" ]]; then
        echo "$iDIR/volume-mute.png"
    elif [[ "$vol" -le 30 ]]; then
        echo "$iDIR/volume-low.png"
    elif [[ "$vol" -le 60 ]]; then
        echo "$iDIR/volume-mid.png"
    else
        echo "$iDIR/volume-high.png"
    fi
}

# Notify
notify_user() {
    get_status
    local icon=$(get_icon "$volume" "$is_muted")
    if [[ "$is_muted" == "true" ]]; then
        notify-send -e -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" "Volume: Muted"
    else
        notify-send -e -h int:value:"$volume" -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" "Volume: $volume%"
    fi
}

# Increase Volume
inc_volume() {
    if [ "$(pamixer --get-mute)" == "true" ]; then
        pamixer -u
    fi
    pamixer -i 5 --allow-boost --set-limit 150 && notify_user
}

# Decrease Volume
dec_volume() {
    if [ "$(pamixer --get-mute)" == "true" ]; then
        pamixer -u
    fi
    pamixer -d 5 && notify_user
}

# Toggle Mute
toggle_mute() {
    pamixer -t
    notify_user
}

# Toggle Mic
toggle_mic() {
    pamixer --default-source -t
    notify_mic_user
}

# Get Microphone Status
get_mic_status() {
    mic_volume=$(pamixer --default-source --get-volume)
    mic_muted=$(pamixer --default-source --get-mute)
}

# Get Mic Icon
get_mic_icon() {
    local muted=$1
    if [[ "$muted" == "true" ]]; then
        echo "$iDIR/microphone-mute.png"
    else
        echo "$iDIR/microphone.png"
    fi
}

# Notify for Microphone
notify_mic_user() {
    get_mic_status
    local icon=$(get_mic_icon "$mic_muted")
    if [[ "$mic_muted" == "true" ]]; then
        notify-send -e -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" "Microphone: Muted"
    else
        notify-send -e -h int:value:"$mic_volume" -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" "Mic Level: $mic_volume%"
    fi
}

# Increase MIC Volume
inc_mic_volume() {
    if [ "$(pamixer --default-source --get-mute)" == "true" ]; then
        pamixer --default-source -u
    fi
    pamixer --default-source -i 5 && notify_mic_user
}

# Decrease MIC Volume
dec_mic_volume() {
    if [ "$(pamixer --default-source --get-mute)" == "true" ]; then
        pamixer --default-source -u
    fi
    pamixer --default-source -d 5 && notify_mic_user
}

# Execute accordingly
case "$1" in
    "--get")
        pamixer --get-volume
        ;;
    "--inc")
        inc_volume
        ;;
    "--dec")
        dec_volume
        ;;
    "--toggle")
        toggle_mute
        ;;
    "--toggle-mic")
        toggle_mic
        ;;
    "--get-icon")
        get_status
        get_icon "$volume" "$is_muted"
        ;;
    "--get-mic-icon")
        get_mic_status
        get_mic_icon "$mic_muted"
        ;;
    "--mic-inc")
        inc_mic_volume
        ;;
    "--mic-dec")
        dec_mic_volume
        ;;
    "--get-mic-vol")
        pamixer --default-source --get-volume
        ;;
    *)
        pamixer --get-volume
        ;;
esac
