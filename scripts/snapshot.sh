#!/bin/sh
# Snapshot window/pane layout + per-pane PWD, one TSV per session.
# Session name is the unique key: re-snapshotting overwrites (one save slot
# per session). Bare run inside tmux snapshots the current session; outside
# tmux an fzf picker picks one; an explicit argument snapshots that session;
# --all snapshots every live session (e.g. pre-reboot).
#
# Scratch panes are never saved: per-pane @scratch=1/@park=1 flags are
# dropped (a window hosting one is saved with layout "-" since the exact
# tree is not representable without it), and the parking session itself is
# excluded wholesale below.
#
# Atomic writes (unique tmp + mv): concurrent saves are safe. No-op while a
# restore is running so half-built sessions are never captured.
#
# pi panes are resolved here, not at restore: a live pi_registry row
# (written by the pi launcher wrapper) matching this server's ident + pane
# id rewrites the program column to pi:<uuid>.
#
# Format (tab separated):
#   s <boot_id>:<server_pid>
#   w <widx> <wactive> <zoomed> <name> <layout|->
#   p <widx> <pidx> <pactive> <path> <curcmd> <pane_id> <left> <top>
set -eu

tbin="${TMUX_BIN:-tmux}"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
[ -e "$dir/.restoring" ] && exit 0
mkdir -p "$dir"

# sessions never snapshotted (case patterns, | separated): the scratch-pane
# parking session (_tmux_scratch) is infrastructure, not work
exclude="tmux_scratch_pane_parking"
# shellcheck disable=SC2254  # unquoted: these are case patterns
excluded() { case "$1" in $exclude) return 0 ;; *) return 1 ;; esac }

case "${1:-}" in
    --all)
        only=$("$tbin" list-sessions -F '#{session_name}' | while IFS= read -r s; do
            excluded "$s" || printf '%s\n' "$s"
        done)
        ;;
    "")
        if [ -n "${TMUX:-}" ]; then
            only=$("$tbin" display-message -p '#{session_name}')
            excluded "$only" && { echo "session '$only' is excluded from snapshots" >&2; exit 1; }
        else
            only=$("$tbin" list-sessions -F '#{session_name}' 2>/dev/null |
                while IFS= read -r s; do excluded "$s" || printf '%s\n' "$s"; done |
                fzf --prompt='Snapshot session: ') || exit 0
        fi
        ;;
    --*)
        echo "usage: snapshot.sh [--all | <session>]" >&2
        exit 1
        ;;
    *)
        only="$1"
        excluded "$only" && { echo "session '$only' is excluded from snapshots" >&2; exit 1; }
        ;;
esac

ident="$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null || echo noboot):$("$tbin" display-message -p '#{pid}')"

# pane rows are buffered per window so a scratch/parked pane seen at any
# index degrades its window's layout before the window row is written;
# windows with no surviving panes (a parked scratch window) vanish entirely.
# awk writes unique tmp files and a tmp<TAB>key manifest on stdout; the mv
# runs in sh so filenames with quotes/spaces can't break system() quoting.
"$tbin" list-panes -a -F '#{session_name}	#{window_index}	#{window_active}	#{window_zoomed_flag}	#{window_name}	#{window_layout}	#{pane_index}	#{pane_active}	#{pane_current_path}	#{pane_current_command}	#{pane_id}	#{@scratch}	#{pane_left}	#{pane_top}	#{@park}' |
awk -F'\t' -v out="$dir" -v me="$$" -v ident="$ident" -v regf="$dir/pi_registry" -v only="$only" '
function safe(s) { gsub(/\t/, " ", s); return s }
function flush(s,    k, f, wi, lay, n, i) {
    if (s == "") return
    k = s
    gsub(/[^A-Za-z0-9_-]/, "_", k)
    f = out "/.tmp." k "." me
    printf "s\t%s\n", ident > f
    for (wi = 0; wi <= maxwi[s]; wi++) {
        if (!((s, wi) in wname)) continue
        if (nkeep[s, wi] == 0) continue
        lay = scratchin[s, wi] ? "-" : wlayout[s, wi]
        printf "w\t%d\t%d\t%d\t%s\t%s\n", wi, wact[s, wi], zoom[s, wi], wname[s, wi], lay >> f
        n = split(panes[s, wi], rows, "\n")
        for (i = 1; i <= n; i++) print rows[i] >> f
    }
    close(f)
    print f "\t" out "/" k ".tsv"
}
BEGIN {
    n = split(only, wantarr, "\n")
    for (i = 1; i <= n; i++) want[wantarr[i]] = 1
    if (regf != "") while ((getline rl < regf) > 0) { split(rl, r, "\t"); if (r[1] == ident) reg[r[2]] = r[3] }
}
$12 == "1" || $15 == "1" { scratchin[$1, $2] = 1; next }
{
    sess = safe($1)
    if (only != "" && !(sess in want)) next
    if (sess != prev) { flush(prev); prev = sess }
    wi = $2 + 0
    if (wi > maxwi[sess]) maxwi[sess] = wi
    if (!((sess, wi) in wname)) {
        wname[sess, wi] = safe($5); wact[sess, wi] = $3
        zoom[sess, wi] = $4; wlayout[sess, wi] = $6; nkeep[sess, wi] = 0
    }
    nkeep[sess, wi]++
    cmd = ($11 in reg) ? "pi:" reg[$11] : $10
    row = sprintf("p\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s", wi, $7, $8, safe($9), cmd, $11, $13, $14)
    panes[sess, wi] = (panes[sess, wi] == "" ? "" : panes[sess, wi] "\n") row
}
END { flush(prev) }
' | while IFS="$(printf '\t')" read -r tmp final; do
    mv -f "$tmp" "$final"
done
