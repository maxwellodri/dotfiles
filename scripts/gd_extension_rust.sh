#!/bin/sh
git_root=$(git rev-parse --show-toplevel)
rustup run nightly cargo build --manifest-path="$git_root/rust/Cargo.toml"
