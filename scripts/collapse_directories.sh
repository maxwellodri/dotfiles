#!/bin/bash
find "$1" -type f -exec sh -c 'mv "$@" $1' _ {} +
find "$1" -depth -exec rmdir {} +

