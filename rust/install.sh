#!/bin/bash
if [ -z "$bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit 1
fi

cd "$dotfiles/rust/dirsort" || exit 1
echo "Building dir_sort..."
cargo build --release || exit 1
ln -sf "$dotfiles/rust/dirsort/target/release/dirsort" "$bin"
echo "Linked $(realpath "$dotfiles/rust/dirsort/target/release/dirsort") to $bin"

cd "$dotfiles/rust/faucet" || exit 1
echo "Building faucet..."
cargo build --release || exit 1
ln -sf "$dotfiles/rust/faucet/target/release/faucet" "$bin/faucet"
echo "Linked $(realpath "$dotfiles/rust/faucet/target/release/faucet") to $bin"
