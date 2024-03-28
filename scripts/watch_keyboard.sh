#!/bin/bash

while true; do
    xmodmap -e "clear Lock"
    xmodmap -e "keycode 66 = Escape"
    sleep 0.1
done
