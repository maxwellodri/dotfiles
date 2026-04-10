#!/usr/bin/env bash

tmux_info=""
if [ -n "$TMUX" ]; then
    tmux_info=" in tmux session \`$(tmux display-message -p '#S')\`"
fi

notify-send --hint string:x-canonical-private-synchronous:notify-user-coding-agent "Human, I am done 🥹${tmux_info}"

ffmpeg -f lavfi -i "sine=frequency=400:duration=0.2" \
    -f lavfi -i "sine=frequency=800:duration=0.2" \
    -f lavfi -i "sine=frequency=400:duration=0.2" \
    -f lavfi -i "sine=frequency=800:duration=0.2" \
    -f lavfi -i "sine=frequency=400:duration=0.2" \
    -filter_complex "[0:a][1:a][2:a][3:a][4:a]concat=n=5:v=0:a=1[out]" \
    -map "[out]" -f s16le -ar 44100 -ac 1 - \
    2>/dev/null | paplay --raw --rate=44100 --channels=1 --format=s16le
