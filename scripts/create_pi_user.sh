#!/bin/sh

help() {
    cat <<'EOF'
create_pi_user.sh — set up a 'pi' user for running AI coding agents

Usage: sudo ./create_pi_user.sh [--clear] [--secrets "secret1,secret2,..."] [dir1 dir2 ...]

Options:
  --clear               Revoke all pi ACLs from $REAL_HOME and any listed dirs, then exit
  --secrets "s1,s2,..." Secrets to copy from $REAL_USER's pass store to pi's pass store
                        (comma-separated list of pass entry names)

Examples:
  sudo ./create_pi_user.sh                                                # interactive
  sudo ./create_pi_user.sh /home/you/source/project                       # specific dirs
  sudo ./create_pi_user.sh $(qz list --clean --tmux)                      # from command output
  sudo ./create_pi_user.sh --clear                                        # revoke read on $HOME
  sudo ./create_pi_user.sh --clear $(qz list --clean --tmux)              # revoke + write dirs
  sudo ./create_pi_user.sh --secrets "zai_opencode_api_key" $(qz list --clean --tmux)

What it does:
  1. Creates user 'pi' with your current shell, home /home/pi/
  2. Prompts for pi's password
  3. Sets up pi's GPG key and password store (from $REAL_USER's pass store)
  4. Copies specified secrets from $REAL_USER's pass store to pi's
  5. Grants pi read access to $SUDO_USER's home (so it inherits shell prefs)
  6. Grants pi read+write access to any dirs passed as arguments
  7. Adds git safe.directory entries for dotfiles and write dirs
  8. Runs dotfiles install as pi (--other-user: symlinks + bin scripts only)
EOF
}

set -e

# Handle --help before root check so it works without sudo
for arg in "$@"; do
    case "$arg" in
        --help|-h) help; exit 0 ;;
    esac
done

# --- Must run as root ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo: sudo $0 [options] [dir1 dir2 ...]"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_SHELL=$(getent passwd "$REAL_USER" | cut -d: -f7)
PI_USER="pi"
PI_HOME="/home/$PI_USER"
PI_GPG_ID="pi-user"
PI_GPG_EMAIL="pi@localhost"

# --- Parse arguments ---
clear_mode=false
secrets_list=""
write_dirs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --clear)   clear_mode=true; shift ;;
        --secrets) secrets_list="$2"; shift 2 ;;
        --help)    help; exit 0 ;;
        *)         write_dirs="$write_dirs $1"; shift ;;
    esac
done

# --- Clear mode: revoke all pi ACLs ---
if [ "$clear_mode" = true ]; then
    echo "Revoking $PI_USER ACLs from $REAL_HOME ..."
    setfacl -R -x u:"$PI_USER" "$REAL_HOME"
    setfacl -R -x d:u:"$PI_USER" "$REAL_HOME"

    if [ -n "$write_dirs" ]; then
        for dir in $write_dirs; do
            echo "Revoking $PI_USER ACLs from $dir"
            setfacl -R -x u:"$PI_USER" "$dir"
            setfacl -R -x d:u:"$PI_USER" "$dir"
        done
    fi

    echo ""
    echo "All $PI_USER ACLs revoked."
    exit 0
fi

# --- Create the user ---
if id "$PI_USER" >/dev/null 2>&1; then
    echo "User '$PI_USER' already exists — skipping creation."
else
    echo "Creating user '$PI_USER' with shell $REAL_SHELL, home $PI_HOME"
    useradd -m -d "$PI_HOME" -s "$REAL_SHELL" "$PI_USER"
    echo "Set a password for $PI_USER:"
    passwd "$PI_USER"
    echo ""
fi

# --- Setup pi's GPG key and password store ---
# Extract pi's GPG key from REAL_USER's pass store, import into pi's keyring
if sudo -u "$REAL_USER" pass show pi-user-gpg-key >/dev/null 2>&1; then
    echo "Setting up $PI_USER's GPG keyring ..."
    # Export from REAL_USER's pass, import into pi's keyring
    sudo -u "$REAL_USER" pass show pi-user-gpg-key | sudo -u "$PI_USER" gpg --batch --import 2>/dev/null

    # Trust the key ultimately
    PI_KEY_FINGERPRINT=$(sudo -u "$PI_USER" gpg --list-keys --with-colons "$PI_GPG_EMAIL" 2>/dev/null | grep '^fpr' | head -1 | cut -d: -f10)
    if [ -n "$PI_KEY_FINGERPRINT" ]; then
        echo "$PI_KEY_FINGERPRINT:6:" | sudo -u "$PI_USER" gpg --import-ownertrust 2>/dev/null
    fi

    # Initialize pi's password store with pi's GPG key
    if [ ! -d "$PI_HOME/.password-store" ]; then
        echo "Initializing $PI_USER's password store ..."
        sudo -u "$PI_USER" PASSWORD_STORE_DIR="$PI_HOME/.password-store" pass init "$PI_KEY_FINGERPRINT" 2>/dev/null
    else
        echo "$PI_USER's password store already exists — skipping init."
    fi
else
    echo "Warning: pi-user-gpg-key not found in $REAL_USER's pass store."
    echo "  Skipping GPG/password store setup."
    echo "  To set up later: generate a GPG key for pi, export to your pass store as 'pi-user-gpg-key', then re-run."
fi

# --- Copy secrets from REAL_USER's pass store to pi's ---
if [ -n "$secrets_list" ] && [ -d "$PI_HOME/.password-store" ]; then
    echo ""
    echo "Copying secrets to $PI_USER's password store ..."
    saved_IFS="$IFS"; IFS=","
    set -f
    for secret in $secrets_list; do
        set +f
        IFS="$saved_IFS"
        if sudo -u "$REAL_USER" pass show "$secret" >/dev/null 2>&1; then
            echo "  Copying: $secret"
            sudo -u "$REAL_USER" pass show "$secret" | sudo -u "$PI_USER" PASSWORD_STORE_DIR="$PI_HOME/.password-store" pass insert -fe "$secret" 2>/dev/null
        else
            echo "  Warning: '$secret' not found in $REAL_USER's pass store, skipping."
        fi
    done
    echo "Done."
elif [ -n "$secrets_list" ] && [ ! -d "$PI_HOME/.password-store" ]; then
    echo "Warning: --secrets provided but pi's password store not initialized. Skipping."
fi

# --- ACL: pi can read $REAL_USER's home ---
echo ""
echo "Granting $PI_USER read access to $REAL_HOME ..."
setfacl -R -m u:"$PI_USER":rX "$REAL_HOME"
setfacl -R -d -m u:"$PI_USER":rX "$REAL_HOME"
echo "Done."

# --- ACL: pi gets write access to specified dirs ---
# If no args, prompt interactively
if [ -z "$write_dirs" ]; then
    echo ""
    echo "Enter directories $PI_USER should be able to write to (space-separated, or blank to skip):"
    read -r write_dirs
fi

if [ -n "$write_dirs" ]; then
    for dir in $write_dirs; do
        if [ ! -d "$dir" ]; then
            echo "Warning: $dir does not exist, creating it..."
            mkdir -p "$dir"
            chown "$REAL_USER":"$REAL_USER" "$dir"
        fi
        echo "Granting $PI_USER read+write access to $dir"
        setfacl -R -m u:"$PI_USER":rwX "$dir"
        setfacl -R -d -m u:"$PI_USER":rwX "$dir"
    done
    echo "Done."
else
    echo "No write directories specified — skipping."
fi

# --- Git safe.directory for REAL_USER's repos ---
echo ""
echo "Configuring git safe.directory for $PI_USER ..."
DOTFILES_DIR="$REAL_HOME/source/dotfiles"
sudo -u "$PI_USER" git config --global --add safe.directory "$DOTFILES_DIR"
for dir in $write_dirs; do
    # Add any arg that looks like a git repo (has .git or is under source/)
    sudo -u "$PI_USER" git config --global --add safe.directory "$dir"
done
echo "Done."

# --- Run dotfiles install as pi ---
if [ -d "$DOTFILES_DIR" ]; then
    echo ""
    echo "Running dotfiles install as $PI_USER (--other-user) ..."
    sudo -u "$PI_USER" zsh -lc "sh $DOTFILES_DIR/install.sh pc --other-user $PI_USER"
    echo "Done."
else
    echo "Warning: $DOTFILES_DIR not found, skipping dotfiles install."
fi

# --- Summary ---
echo ""
echo "========================================="
echo "  $PI_USER user setup complete"
echo "========================================="
echo "  Home:       $PI_HOME"
echo "  Shell:      $REAL_SHELL"
echo "  Run as pi:  sudo -u $PI_USER zsh"
echo "  Read:       $REAL_HOME"
if [ -d "$PI_HOME/.password-store" ]; then
    echo "  Pass store: $PI_HOME/.password-store"
fi
if [ -n "$secrets_list" ]; then
    echo "  Secrets:   $secrets_list"
fi
if [ -n "$write_dirs" ]; then
    echo "  Write:     $write_dirs"
fi
echo "========================================="
