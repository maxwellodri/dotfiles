#!/bin/sh
rm -f ~/.cache/tsp_ytdlp/*
tmux kill-session -t tsp_ytdlp
tmux new-session -d -s tsp_ytdlp 'tsp_ytdlp --daemon'
