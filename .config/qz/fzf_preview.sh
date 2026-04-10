#!/bin/bash
#set -euo pipefail # Exit on error, undefined variable, or pipe failure

if [ -z "${PROJECT_PATH_ENV_VAR:-}" ]; then
    echo "Error: PROJECT_PATH_ENV_VAR is not set." >&2
    echo "This script expects fzf to set PROJECT_PATH_ENV_VAR." >&2
    exit 1
fi

if [ -z "${1:-}" ]; then
    echo "Error: No relative path argument provided." >&2
    echo "Usage: $0 <relative_path_to_preview>" >&2
    exit 1
fi

TARGET_RELPATH="$1" # The item selected by fzf (e.g., "src/main.py")
BASE_DIR="${PROJECT_PATH_ENV_VAR}" # Get base dir from env var set by fzf's --preview

# Construct the full path to the item
FULL_PATH="$BASE_DIR/$TARGET_RELPATH"

# Check if the target actually exists
if [ ! -e "$FULL_PATH" ]; then
    # Output to stderr so fzf might show it, or at least not a blank preview
    echo "Preview Error: Path not found." >&2
    echo "Item (relative): $TARGET_RELPATH" >&2
    echo "Resolved Base:   $BASE_DIR" >&2
    echo "Attempted Path:  $FULL_PATH" >&2
    exit 0 # Exit cleanly for fzf, but the error message indicates a problem
fi

if [[ -d "$FULL_PATH" ]]; then
    # For directories: try 'tree' with color, level 2, no report. Fallback to 'ls'.
    # 2>/dev/null silences errors if tree/ls options fail or tool missing
    tree -C "$FULL_PATH" -L 2 --noreport 2>/dev/null || ls -ApF --color=always "$FULL_PATH" 2>/dev/null || echo "Could not list directory."
elif command -v xdg-mime >/dev/null && command -v file >/dev/null; then
    # It's a file; get its mimetype and default handler
    MIMETYPE=$(file --dereference --brief --mime-type "$FULL_PATH" 2>/dev/null || echo "application/octet-stream")
    DEFAULT_HANDLER=$(xdg-mime query default "$MIMETYPE" 2>/dev/null || echo "unknown_handler.desktop")

    # Check if "neovide" (case-insensitive) is part of the default handler string
    if echo "$DEFAULT_HANDLER" | grep -qi "neovide"; then
        # "Text file" via Neovide: preview with 'bat'. Fallback to 'cat'.
        bat --paging=never --color=always --style=full --line-range :500 "$FULL_PATH" 2>/dev/null || cat "$FULL_PATH" 2>/dev/null || echo "Could not display text file."
    else
        # Not a directory, and not a "Neovide text file"
        echo "File:             $TARGET_RELPATH"
        echo "MIME Type:        $MIMETYPE"
        echo "Default Handler:  $DEFAULT_HANDLER"
        # If it's a generic text/* mime type, show a brief snippet
        if [[ "$MIMETYPE" == text/* ]]; then
            echo "--- Snippet (up to 20 lines) ---"
            head -n 20 "$FULL_PATH" 2>/dev/null
        fi
    fi
else
    # Fallback if xdg-mime or file command is not available
    echo "File: $TARGET_RELPATH"
    echo "(xdg-mime/file commands missing for detailed type check)"
    # Basic heuristic for "text-like" content.
    # Check if first 1KB has >50% printable (excluding NUL & most control chars)
    if head -c 1024 "$FULL_PATH" 2>/dev/null | LC_ALL=C tr -dc '[:print:][:space:]' | wc -c | awk -v total_bytes="$(head -c 1024 "$FULL_PATH" 2>/dev/null | wc -c)" '{ if (total_bytes > 0 && ($1 * 100 / total_bytes) > 50) exit 0; else exit 1; }'; then
        echo "--- Snippet (basic text check, up to 20 lines) ---"
        head -n 20 "$FULL_PATH" 2>/dev/null
    else
        echo "(Content appears to be binary or empty)"
    fi
fi
