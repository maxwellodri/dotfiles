#!/bin/sh
#adds wrappers and the like to path
#assumes $bin is in path -> i.e. need makesymlink script to have already been run
mkdir -p $bin
cd $dotfiles/bin
for file in $(find *); do
    ln -sf "$(realpath $file)" "$bin/$file"
done


