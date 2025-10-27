#!/usr/bin/env bash
# ripgrep + fzf text search with $EDITOR integration
# Usage: rg-fzf.sh [search_term] [rg_options...]

# Determine working directory: git root if in repo, otherwise PWD
WORK_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$WORK_DIR" || exit 1

# Use first arg as search term if provided, otherwise use empty string for live grep
INITIAL_QUERY="${1:-}"
shift

EDITOR="${EDITOR:-vim}"

# Ripgrep command with file type colors
RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case --colors \"match:style:bold\" --colors \"match:fg:white\" --colors \"path:style:underline\" --colors \"path:fg:yellow\""

# Run fzf with ripgrep
PREVIEW_SCRIPT="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/fzf_preview.sh"
SELECTED=$(
  FZF_DEFAULT_COMMAND="$RG_PREFIX $(printf %q "$INITIAL_QUERY") $*" \
  fzf --ansi \
      --disabled \
      --query "$INITIAL_QUERY" \
      --bind "change:reload:sleep 0.1; $RG_PREFIX {q} $* || true" \
      --bind "ctrl-u:preview-page-up,ctrl-d:preview-page-down" \
      --delimiter : \
      --preview "env PROJECT_PATH_ENV_VAR=$WORK_DIR $PREVIEW_SCRIPT {1}" \
      --preview-window 'right,60%,border-rounded,+{2}+3/3,~3' \
      --algo=v2 \
      --border=rounded \
      --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
      --color=fg:#cdd6f4,header:#f38ba8,info:#cba6ac,pointer:#f5e0dc \
      --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6ac,hl+:#f38ba8 \
      --cycle
)

# Exit if nothing selected (user pressed ESC or Ctrl+C)
[[ -z "$SELECTED" ]] && exit 0

# Strip ANSI codes before parsing
SELECTED_CLEAN=$(echo "$SELECTED" | sed 's/\x1b\[[0-9;]*m//g')
FILE=$(echo "$SELECTED_CLEAN" | cut -d: -f1)
LINE=$(echo "$SELECTED_CLEAN" | cut -d: -f2)
COL=$(echo "$SELECTED_CLEAN" | cut -d: -f3)

# Open in editor (all files are pre-filtered to only include editor-compatible files)
case "$EDITOR" in
  nvim|vim)
    "$EDITOR" "+call cursor($LINE, $COL)" "$FILE"
    ;;
  *)
    "$EDITOR" "+$LINE" "$FILE"
    ;;
esac
