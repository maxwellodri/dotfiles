#!/bin/bash
if [ -z "$bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit 1
fi

# donnie (headless NixOS VPS) builds only the terminal tools — herald is a
# notification daemon, xidle needs X11 headers that aren't on a server.
tag="${dotfile_tag:-}"
[ -z "$tag" ] && tag="$(cat "$dotfiles/.dotfile_tag" 2>/dev/null || true)"
case "$tag" in
    donnie) crates="dirsort qz" ;;
    *)      crates="dirsort qz herald xidle" ;;
esac

for crate in $crates; do
    cd "$dotfiles/rust/$crate" || exit 1
    echo "Building $crate..."
    cargo build --release || exit 1
    ln -sf "$dotfiles/rust/$crate/target/release/$crate" "$bin"
    echo "Linked $(realpath "$dotfiles/rust/$crate/target/release/$crate") to $bin"
done
