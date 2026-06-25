#!/usr/bin/env bash
while :; do
    playerctl --follow --player=playerctld metadata \
        --format $'{{status}}\t{{artist}}\t{{title}}' 2>/dev/null \
    | while IFS=$'\t' read -r status artist title; do
        if [[ "$status" == "Playing" ]]; then
            printf '{"text":" ▶ %s ","class":"playing"}\n' \
                "${artist:+$artist - }$title"
        else
            printf '\n'
        fi
    done
    printf '\n'   # emit empty when player dies
    sleep 1
done
