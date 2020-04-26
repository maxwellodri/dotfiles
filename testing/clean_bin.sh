#!/bin/sh

for file in $bin/*
do
    if [ -f $file ]; then
        unlink $file
    fi
    if [ -d $file ]; then
        unlink $file
    fi

done

