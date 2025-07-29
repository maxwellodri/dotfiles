#!/bin/bash
if [ -z "$bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit 1
fi
cd "$dotfiles/rust/dirsort" || exit 1
cargo build --release || exit 1
ln -sf "$dotfiles/rust/dirsort/target/release/dirsort" "$bin"
echo "Linked $(realpath "$dotfiles/rust/dirsort/target/release/dirsort") to $bin"
cd "$dotfiles/rust/text_handler" || exit 1
echo "Building text_handler..."
cargo build --release
ln -sf "$dotfiles/rust/text_handler/target/release/text_handler" "$bin/text_handler"

