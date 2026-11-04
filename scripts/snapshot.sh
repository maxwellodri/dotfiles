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
if [ -e "$dir/.restoring" ]; then
    # fresh marker: a restore is running right now
    if find "$dir/.restoring" -mmin -5 2>/dev/null | grep -q .; then
        exit 0
    fi
    # stale: the restore died without its trap (kill -9, power loss)
    if find "$dir/.restoring" -mmin -5 2>/dev/null | grep -q .; then
        exit 0
    fi
    echo "snapshot.sh: stale .restoring marker — bypassing" >&2
    rm -f "$dir/.restoring"
fi
mkdir -p "$dir"

# sessions never snapshotted (glob patterns, whitespace separated): the
# scratch-pane parking session (_tmux_scratch) and restore's id-burner are
# infrastructure, not work
exclude="tmux_scratch_pane_parking blithe-idburn"
excluded() {
    for pat in $exclude; do
        # shellcheck disable=SC2254  # unquoted: these are case patterns
        case "$1" in $pat) return 0 ;; esac
    done
    return 1
}

case "${1:-}" in
    --all)
        only=$("$tbin" list-sessions -F '#{session_name}' | while IFS= read -r s; do
            excluded "$s" || printf '%s\n' "$s"
        done)
        [ -n "$only" ] || { echo "no sessions to snapshot" >&2; exit 0; }
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

# Two pane programs hide behind wrapper scripts (curcmd reports the shell):
# pi (registry gives the exact session uuid) and nvim (scripts/nvim runs
# /usr/bin/nvim as a child). Registry rows are verified by walking the
# pane's process tree — a stale row from a killed pane must not hijack a
# recycled pane id. nvim is tagged by the same walk on shell-idle panes;
# nvim typed at a zsh prompt reports curcmd=nvim natively and needs nothing.
tree_has() { # $1 = pane pid, $2 = process basename to match (argv0/argv1)
    seen=" $1 "
    frontier=$1
    depth=0
    while [ -n "$frontier" ] && [ "$depth" -lt 12 ]; do
        next=""
        for p in $frontier; do
            if [ -r "/proc/$p/cmdline" ] && tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | head -2 | grep -qx "\(.*/\)\?$2"; then
                return 0
            fi
            for k in $(pgrep -P "$p" 2>/dev/null); do
                case "$seen" in *" $k "*) ;; *) seen="$seen$k "; next="$next $k" ;; esac
            done
        done
        frontier=${next# }
        depth=$((depth + 1))
    done
    return 1
}
regf=""
nvf=$(mktemp)
tab=$(printf '\t')
"$tbin" list-panes -a -F "#{pane_id}${tab}#{pane_pid}${tab}#{pane_current_command}" > "$nvf.dump" 2>/dev/null || true
pidir="${XDG_STATE_HOME:-$HOME/.local/state}/pi/sessions"
keepf=""
if [ -f "$dir/pi_registry" ]; then
    regf=$(mktemp)
    keepf=$(mktemp)
    # A row joins this snapshot only when its pane still runs pi behind its
    # wrapper shell ("man pi" / "cat scripts/pi" would otherwise verify via
    # argv[1] and hijack the pane). Rows survive gc while either verified
    # live or their session file still exists — the latter also keeps rows
    # of panes too fresh for the process walk to see yet.
    while IFS="$(printf '\t')" read -r rident rpane ruuid; do
        verified=""
        if [ "$rident" = "$ident" ]; then
            rcmd=$(awk -F'\t' -v k="$rpane" '$1 == k { print $3; exit }' "$nvf.dump")
            case "$rcmd" in
                sh|bash|zsh|dash|fish) ;;
                *) rcmd="" ;;
            esac
            if [ -n "$rcmd" ]; then
                pid=$(awk -F'\t' -v k="$rpane" '$1 == k { print $2; exit }' "$nvf.dump")
                [ -n "$pid" ] && tree_has "$pid" pi && verified=1
            fi
        fi
        if [ -n "$verified" ]; then
            printf '%s\t%s\t%s\n' "$rident" "$rpane" "$ruuid" >> "$regf.rows"
        fi
        if [ -n "$verified" ] || [ -n "$(ls "$pidir"/*_"$ruuid".jsonl 2>/dev/null)" ]; then
            printf '%s\t%s\t%s\n' "$rident" "$rpane" "$ruuid" >> "$keepf"
        fi
    done < "$dir/pi_registry"
    [ -f "$regf.rows" ] || : > "$regf.rows"
    mv -f "$regf.rows" "$regf"
    # unique keep name: concurrent snapshots both rewrite the registry
    if [ -f "$keepf" ]; then
        mv -f "$keepf" "$dir/pi_registry" 2>/dev/null || true
    fi
fi

while IFS="$(printf '\t')" read -r rpane pid rcmd; do
    case "$rcmd" in
        sh|bash|zsh|dash|fish) ;;
        *) continue ;;
    esac
    tree_has "$pid" nvim && printf '%s\t%s\n' "$rpane" "$rcmd" >> "$nvf.tags"
done < "$nvf.dump"
[ -f "$nvf.tags" ] && mv -f "$nvf.tags" "$nvf" || : > "$nvf"
rm -f "$nvf.dump"

# pane rows are buffered per window so a scratch/parked pane seen at any
# index degrades its window's layout before the window row is written;
# windows with no surviving panes (a parked scratch window) vanish entirely.
# awk writes unique tmp files and a tmp<TAB>key manifest on stdout; the mv
# runs in sh so filenames with quotes/spaces can't break system() quoting.
"$tbin" list-panes -a -F '#{session_name}	#{window_index}	#{window_active}	#{window_zoomed_flag}	#{window_name}	#{window_layout}	#{pane_index}	#{pane_active}	#{pane_current_path}	#{pane_current_command}	#{pane_id}	#{@scratch}	#{pane_left}	#{pane_top}	#{@park}' |
awk -F'\t' -v out="$dir" -v me="$$" -v ident="$ident" -v regf="$regf" -v nvf="$nvf" -v only="$only" '
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
    while ((getline nl < nvf) > 0) { split(nl, nvrow, "\t"); nvtag[nvrow[1]] = 1 }
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
    cmd = ($11 in reg) ? "pi:" reg[$11] : ($11 in nvtag) ? "nvim" : $10
    row = sprintf("p\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s", wi, $7, $8, safe($9), cmd, $11, $13, $14)
    panes[sess, wi] = (panes[sess, wi] == "" ? "" : panes[sess, wi] "\n") row
}
END { flush(prev) }
' | while IFS="$(printf '\t')" read -r tmp final; do
    mv -f "$tmp" "$final"
done
rm -f "$nvf" 2>/dev/null || true
[ -n "${regf:-}" ] && rm -f "$regf" 2>/dev/null || true
# gc: per-cwd nvim sessions untouched for a month are dead dirs' state
find "$dir/nvim" -name '*.vim' -type f -mtime +30 -delete 2>/dev/null || true
