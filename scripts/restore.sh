#!/bin/sh
# Restore a session from snapshot.sh's TSV. Panes whose program is in the
# allowlist get it relaunched (pi:<uuid> rows resume that pi session); others
# come back as a shell at the saved PWD with "This pane was running X" echoed
# into it. Scratch pane is never restored (absent from the snapshot).
# One TSV per session under ~/.local/state/tmux/, keyed by session name.
# Refuses to run inside tmux and refuses when the session already exists.
#
# Works on a private copy of the TSV with a .restoring marker set, so a
# concurrent snapshot cannot overwrite the file mid-restore and never sees
# the id-burner session.
set -eu

tbin="${TMUX_BIN:-tmux}"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
sess="${1:?session name}"
cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"

key=$(printf '%s' "$sess" | sed 's/[^A-Za-z0-9_-]/_/g')
file="$dir/$key.tsv"
[ -f "$file" ] || { echo "no snapshot for $sess" >&2; exit 1; }
if [ -n "${TMUX:-}" ]; then
    echo "restore.sh runs outside tmux only (sessions must be rebuilt before attaching)" >&2
    exit 1
fi
if "$tbin" has-session -t "=$sess" 2>/dev/null; then
    echo "session $sess already exists" >&2
    exit 1
fi

work=$(mktemp)
trap 'rm -f "$work"; rm -f "$dir/.restoring"' EXIT INT TERM HUP
cp "$file" "$work"
: > "$dir/.restoring"

allow=""
allowlist() {
    [ -n "$allow" ] && { printf '%s\n' "$allow"; return; }
    if [ -f "$cfgdir/programs" ]; then allow=$(cat "$cfgdir/programs"); else allow='pi
nvim'; fi
    printf '%s\n' "$allow"
}
allowed() { case "
$(allowlist)
" in *"
$1
"*) return 0 ;; *) return 1 ;; esac }
is_shell() { case "$1" in zsh|bash|sh|dash|fish) return 0 ;; *) return 1 ;; esac }

# pane command for creation: pi:<uuid> -> resume session; allowed -> relaunch
# (bare pi process shows as "node" from a non-wrapper launch); else none
pane_cmd() { # $1 curcmd
    case "$1" in
        pi:*) printf 'pi --session %s' "${1#pi:}"; return ;;
        node) printf 'pi'; return ;;
    esac
    if allowed "$1" && ! is_shell "$1"; then
        printf '%s' "$1"
    fi
}

pane_dir() { [ -d "$1" ] && printf '%s' "$1" || printf '%s' "$HOME"; }

# tmux 3.7 recycles pane ids once dead; select-layout's pane-to-cell pairing
# is inconsistent when the string's ids are alive. Burn ids past the
# snapshot's max so the string's ids can never match a live pane.
burn_ids() {
    maxid=$(awk -F'\t' '
        $1 == "p" { gsub(/%/, "", $7); if ($7 + 0 > m) m = $7 + 0 }
        $1 == "w" {
            s = $6
            while (match(s, /,[0-9]+[,}\]]/)) {
                v = substr(s, RSTART + 1, RLENGTH - 2) + 0
                if (v > m) m = v
                s = substr(s, RSTART + RLENGTH)
            }
        }
        END { print m + 0 }' "$work")
    if case "$maxid" in *[!0-9]*|"") true ;; *) false ;; esac; then maxid=0; fi
    json_max=$(awk -F'\t' '$1 == "w" && $6 ~ /^\{/ { print $6 }' "$work" |
        jq -r '[.. | objects | select(.t? == "p") | .I] | .[] | gsub("%"; "")' 2>/dev/null |
        sort -n | tail -1)
    [ -n "$json_max" ] && [ "$json_max" -gt "$maxid" ] 2>/dev/null && maxid=$json_max
    alive_max=$("$tbin" list-panes -a -F '#{pane_id}' 2>/dev/null | tr -d '%' | sort -n | tail -1)
    alive_max=${alive_max:-0}
    if [ "$maxid" -ge "$alive_max" ]; then
        "$tbin" kill-session -t "=blithe-idburn" 2>/dev/null || true
        "$tbin" new-session -d -s blithe-idburn -c /tmp
        i=0
        while [ "$i" -le "$maxid" ]; do
            "$tbin" new-window -d -t blithe-idburn
            : > "$dir/.restoring"
            i=$((i + 1))
        done
        "$tbin" kill-session -t blithe-idburn
    fi
}
burn_ids

first_done=0

# window pass: session + windows with their first pane, sized before splits
while IFS="$(printf '\t')" read -r tag wi wact zoom name layout; do
    [ "$tag" = "w" ] || continue
    prow=$(awk -F'\t' -v w="$wi" '$1 == "p" && $2 == w { sub(/^[^\t]*\t/, ""); print; exit }' "$work")
    IFS="$(printf '\t')" read -r _widx _pidx _pact ppath curcmd _pid _pl _pt <<EOF
$prow
EOF
    cmd=$(pane_cmd "$curcmd")
    d=$(pane_dir "$ppath")
    if [ "$layout" = "-" ]; then
        wx=120
        wy=40
    elif case "$layout" in "{"*) true ;; *) false ;; esac; then
        wx=$(printf '%s' "$layout" | jq -r '.L.w')
        wy=$(printf '%s' "$layout" | jq -r '.L.h')
    else
        base=${layout#*,}
        wx=${base%%x*}
        wy=$(printf '%s' "$base" | sed 's/^[0-9]*x\([0-9]*\),.*/\1/')
    fi
    if [ "$first_done" = "0" ]; then
        first_done=1
        if [ -n "$cmd" ]; then
            "$tbin" new-session -d -s "$sess" -n "$name" -x "$wx" -y "$wy" -c "$d" "$cmd"
        else
            "$tbin" new-session -d -s "$sess" -n "$name" -x "$wx" -y "$wy" -c "$d"
        fi
        # new-session lands at base-index 0; saved index may differ
        [ "$wi" != 0 ] && "$tbin" move-window -s "$sess:0" -t "$sess:$wi"
    else
        if [ -n "$cmd" ]; then
            "$tbin" new-window -d -t "$sess:$wi" -n "$name" -c "$d" "$cmd"
        else
            "$tbin" new-window -d -t "$sess:$wi" -n "$name" -c "$d"
        fi
        "$tbin" resize-window -t "$sess:$wi" -x "$wx" -y "$wy"
    fi
done < "$work"

# pane pass: extra panes in saved order, then geometry + deterministic pairing
for wi in $(awk -F'\t' '$1 == "w" { print $2 }' "$work"); do
    layout=$(awk -F'\t' -v w="$wi" '$1 == "w" && $2 == w { print $6; exit }' "$work")
    zoom=$(awk -F'\t' -v w="$wi" '$1 == "w" && $2 == w { print $4; exit }' "$work")
    tmp=$(mktemp)

    # extra panes (first pane came with the window)
    first=1
    while IFS="$(printf '\t')" read -r pidx pact ppath curcmd pane_id pleft ptop; do
        [ "$first" = "1" ] && { first=0; continue; }
        cmd=$(pane_cmd "$curcmd")
        if [ -n "$cmd" ]; then
            "$tbin" split-window -d -t "$sess:$wi" -c "$(pane_dir "$ppath")" "$cmd"
        else
            "$tbin" split-window -d -t "$sess:$wi" -c "$(pane_dir "$ppath")"
        fi
    done <<EOF
$(awk -F'\t' -v w="$wi" '$1 == "p" && $2 == w { print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9 }' "$work")
EOF

    if [ "$layout" != "-" ]; then
        "$tbin" select-layout -t "$sess:$wi" "$layout"
        # select-layout's pane-to-cell pairing is not trustworthy: fix it by
        # swapping. The k-th leaf cell of the layout string (DFS order) is the
        # k-th saved pane; panes created in saved order have ascending ids.
        "$tbin" list-panes -t "$sess:$wi" -F '#{pane_id}	#{pane_left}	#{pane_top}' > "$tmp.pos"
        awk -F'\t' '{ printf "%d\t%s\t%s\n", substr($1, 2), $2, $3 }' "$tmp.pos" > "$tmp.posn"
        sort -n "$tmp.posn" | cut -f1 > "$tmp.created"
        # leaf cells in tree order: k-th leaf = k-th saved pane
        if case "$layout" in "{"*) true ;; *) false ;; esac; then
            printf '%s' "$layout" | jq -r '[.. | objects | select(.t? == "p")] | .[] | "\(.x)\t\(.y)"' > "$tmp.cells"
        else
            awk -v lay="$layout" 'BEGIN {
                while (match(lay, /[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+/)) {
                    c = substr(lay, RSTART, RLENGTH); split(c, a, ",")
                    print a[2] "\t" a[3]
                    lay = substr(lay, RSTART + RLENGTH)
                }
            }' > "$tmp.cells"
        fi
        i=0
        while IFS="$(printf '\t')" read -r cl ct; do
            want=$(sed -n "$((i + 1))p" "$tmp.created")
            at=$(awk -F'\t' -v l="$cl" -v t="$ct" '$2 == l && $3 == t { print $1; exit }' "$tmp.posn")
            if [ -n "$at" ] && [ "$at" != "$want" ]; then
                "$tbin" swap-pane -s "%$want" -t "%$at"
                awk -F'\t' -v OFS='\t' -v w="$want" -v a="$at" \
                    '{ if ($1 == w) $1 = a; else if ($1 == a) $1 = w } { print }' "$tmp.posn" > "$tmp.posn2"
                mv "$tmp.posn2" "$tmp.posn"
            fi
            i=$((i + 1))
        done < "$tmp.cells"

        # active pane + zoom by saved flags
        aslot=$(awk -F'\t' -v w="$wi" '$1 == "p" && $2 == w { n++; if ($4 == "1") a = n - 1 } END { print a }' "$work")
        if [ -n "$aslot" ]; then
            aid=$(sed -n "$((aslot + 1))p" "$tmp.created")
            "$tbin" select-pane -t "%$aid"
            [ "$zoom" = "1" ] && "$tbin" resize-pane -Z -t "%$aid"
        fi
    else
        "$tbin" select-layout -t "$sess:$wi" tiled 2>/dev/null || true
    fi
    rm -f "$tmp" "$tmp.pos" "$tmp.posn" "$tmp.posn2" "$tmp.created" "$tmp.cells"
done

# session active window last
wact=$(awk -F'\t' '$1 == "w" && $3 == 1 { print $2; exit }' "$work")
[ -n "$wact" ] && "$tbin" select-window -t "$sess:$wact"

# "was running X" notes: only for panes restored as a plain shell (nothing
# was relaunched into them); saved pane order == restored position order
sleep 0.3
for wi in $(awk -F'\t' '$1 == "w" { print $2 }' "$work"); do
    slot=0
    awk -F'\t' -v w="$wi" '$1 == "p" && $2 == w { print $6 }' "$work" |
    while IFS= read -r curcmd; do
        cmd=$(pane_cmd "$curcmd")
        if [ -z "$cmd" ] && [ -n "$curcmd" ] && ! is_shell "$curcmd"; then
            tid=$("$tbin" list-panes -t "$sess:$wi" -F '#{pane_index}' | awk -v s="$slot" 'NR - 1 == s { print $1; exit }')
            [ -n "$tid" ] && "$tbin" send-keys -t "$sess:$wi.$tid" "echo This pane was running $curcmd" Enter
        fi
        slot=$((slot + 1))
    done
done
