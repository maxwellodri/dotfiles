#!/bin/bash
if [ -z "$bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit 1
fi
cd "$dotfiles/rust/dirsort" || exit 1
echo "Building dirsort..."
cargo build --release || exit 1
ln -sf "$dotfiles/rust/dirsort/target/release/dirsort" "$bin"
echo "Linked $(realpath "$dotfiles/rust/dirsort/target/release/dirsort") to $bin"

cd "$dotfiles/rust/qz" || exit 1
echo "Building qz..."
cargo build --release || exit 1
ln -sf "$dotfiles/rust/qz/target/release/qz" "$bin"
echo "Linked $(realpath "$dotfiles/rust/qz/target/release/qz") to $bin"

cd "$dotfiles/rust/herald" || exit 1
echo "Building herald..."
cargo build --release || exit 1
ln -sf "$dotfiles/rust/herald/target/release/herald" "$bin"
echo "Linked $(realpath "$dotfiles/rust/herald/target/release/herald") to $bin"
