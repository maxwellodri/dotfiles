#!/bin/bash
if [ -z "$bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit 1
fi
cd "$dotfiles/rust/dirsort" || exit 1
cargo build --release || exit 1
ln -sf "$dotfiles/rust/dirsort/target/release/dirsort" "$bin"
echo "Linked $(realpath "$dotfiles/rust/dirsort/target/release/dirsort") to $bin"
