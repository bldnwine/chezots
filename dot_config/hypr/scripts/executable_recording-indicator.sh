#!/usr/bin/env bash

if pgrep -f "^gpu-screen-recorder" >/dev/null; then
  echo '{"text": " ", "class": "recording", "tooltip": "Recording"}'
else
  echo '{"text": ""}'
fi
