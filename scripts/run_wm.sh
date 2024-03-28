#!/bin/sh
while [ "$KILLDWM" != "true" ]; do
    ssh-agent dwm
done
