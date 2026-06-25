#!/usr/bin/env bash
# Toggle screen recording: desktop audio only, no webcam, no mic
# Hotkey example: SUPER SHIFT K

OUTPUT_DIR="$HOME/Videos/sr"
mkdir -p "$OUTPUT_DIR"
if [[ ! -d "$OUTPUT_DIR" ]]; then
  notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

screenrecording_active() {
  pgrep -f "^gpu-screen-recorder" >/dev/null
}

if screenrecording_active; then
  # Stop
  pkill -SIGINT -f "^gpu-screen-recorder"
  count=0
  while pgrep -f "^gpu-screen-recorder" >/dev/null && [ $count -lt 50 ]; do
    sleep 0.1
    count=$((count + 1))
  done
  if pgrep -f "^gpu-screen-recorder" >/dev/null; then
    pkill -9 -f "^gpu-screen-recorder"
    notify-send "Screen recording error" "Force-killed — video may be corrupted" -u critical -t 5000
  else
    notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
  fi
  pkill -RTMIN+8 waybar
else
  # Start
  filename="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"

  # Always include desktop audio
  sink=$(pactl get-default-sink)
  monitor="${sink}.monitor"
  audio_arg="-a ${monitor}"

  gpu-screen-recorder -w screen -f 60 -c mp4 ${audio_arg} -o "$filename" &
  disown
  sleep 1.5
  if screenrecording_active; then
    notify-send "Recording started (desktop audio)" -t 1500
    pkill -RTMIN+8 waybar
  else
    notify-send "Failed to start gpu-screen-recorder — check terminal / journalctl" -u critical -t 4000
  fi
fi
