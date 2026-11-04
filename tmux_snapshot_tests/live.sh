#!/bin/bash
# Live integration test against the REAL tmux server (not a private socket).
# Creates session blithe_bilby_tmux_snapshot_test, fills it (nvim, real pi,
# shells, shown scratch pane), snapshots, kills the session, restores,
# verifies, cleans up. All state isolated under /tmp/pi-tmux-test (removed).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
S=blithe_bilby_tmux_snapshot_test
SB=/tmp/pi-tmux-test
PROJ=/tmp/blithe-live
T=tmux
fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
poll() {
    local secs=$1 i=0 out
    shift
    while [ "$i" -lt "$secs" ]; do
        out=$(sh -c "$*" 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return 0; }
        sleep 1; i=$((i + 1))
    done
    return 1
}

# isolated state tree; the pi wrapper demands symlinks for session dirs
rm -rf "$SB" "$PROJ"
mkdir -p "$SB/tmux" "$SB/pi" "$SB/sessions-real" "$PROJ"
ln -s "$SB/sessions-real" "$SB/pi/sessions"
ln -s "$SB/sessions-real" "$SB/pi/archived_sessions"
printf 'LIVE_MARKER_ALPHA line one\n' > "$PROJ/la.txt"
printf 'LIVE_MARKER_BETA line two\n' > "$PROJ/lb.txt"
X="XDG_STATE_HOME=$SB"

"$T" kill-session -t "=$S" 2>/dev/null || true

### build
"$T" new-session -d -x 200 -y 50 -s "$S" -n work -c "$PROJ"
"$T" split-window -h -t "$S":0 -c "$PROJ"
"$T" split-window -v -t "$S":0.0 -c "$PROJ"
"$T" resize-pane -t "$S":0.0 -x 60
"$T" select-pane -t "$S":0.2
"$T" new-window -d -t "$S":1 -n host -c "$PROJ"
"$T" split-window -h -t "$S":1 -c "$PROJ"
"$T" set-option -p -t "$S":1.1 @scratch 1
"$T" set-option -p -t "$S":1.1 @scratch-origin "$("$T" display-message -p -t "$S" '#{session_id}')"
"$T" select-pane -t "$S":1.0

# nvim: bare + :e (autosave path), stays running for the snapshot
"$T" send-keys -t "$S":0.0 "$X nvim" Enter
poll 40 "$T capture-pane -p -t $S:0.0 | grep -c NORMAL" || fail "nvim never ready"
"$T" send-keys -t "$S":0.0 ':e la.txt' Enter
poll 15 "$T capture-pane -p -t $S:0.0 | grep -c LIVE_MARKER" || true
"$T" send-keys -t "$S":0.0 ':e lb.txt' Enter
poll 15 "$T capture-pane -p -t $S:0.0 | grep -c LIVE_MARKER" || true
sha=$(python3 -c "import hashlib;print(hashlib.sha256(b'$PROJ').hexdigest())")
[ -f "$SB/tmux/nvim/$sha.vim" ] && pass "nvim autosaved while running" || fail "no nvim session file"

# real pi through the wrapper, isolated sessions
"$T" send-keys -t "$S":0.1 "$X pi" Enter
poll 90 "$T capture-pane -p -t $S:0.1 | grep -c 'MCP:'" || fail "pi UI never ready"
"$T" send-keys -t "$S":0.1 'reply with just: papaya' Enter
r=$(poll 150 "$T capture-pane -p -t $S:0.1 | grep -c papaya")
[ -n "$r" ] && pass "pi replied" || fail "pi never replied"
grep -q . "$SB/tmux/pi_registry" && pass "registry row written (extension)" || fail "no registry row"

# a noteworty non-allowlisted program
"$T" send-keys -t "$S":0.2 'sleep 900' Enter
sleep 1

### snapshot (explicit name; state under SB)
expected=$("$T" list-panes -t "$S" -F '#{window_index}	#{pane_index}	#{pane_left},#{pane_top},#{pane_width}x#{pane_height}	#{pane_current_path}	#{@scratch}' | awk -F'\t' '$5 != "1" {print}' | sort)
env -u TMUX XDG_STATE_HOME=$SB ~/bin/snapshot.sh "$S" || fail "snapshot exited nonzero"
TSV="$SB/tmux/$S.tsv"
[ -f "$TSV" ] && pass "snapshot written" || fail "no TSV"
grep -q "pi:" "$TSV" && pass "pi:<uuid> recorded" || fail "pi not recorded"
grep -q "	nvim	" "$TSV" && pass "nvim tagged" || fail "nvim not tagged"
awk -F'\t' '$1 == "p" && $2 == 1 { n++ } END { exit !(n == 1) }' "$TSV" && pass "scratch pane dropped" || fail "scratch not dropped"

### kill, restore, verify
"$T" kill-session -t "=$S"
i=0
while "$T" has-session -t "=$S" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
env -u TMUX XDG_STATE_HOME=$SB ~/bin/restore.sh "$S" 2>"$SB/restore.err" || { fail "restore exited nonzero"; cat "$SB/restore.err"; }
"$T" set-option -t "$S" remain-on-exit on 2>/dev/null || true
( for i in $(seq 30); do echo "t=$((i / 2)): $($T list-panes -t "$S":0 -F '#{pane_index}:#{pane_current_command}:#{pane_dead} ' 2>/dev/null || echo GONE)"; sleep 0.5; done ) > "$SB/watch.log" &
WW=$!
sleep 8

got=$("$T" list-panes -t "$S" -F '#{window_index}	#{pane_index}	#{pane_left},#{pane_top},#{pane_width}x#{pane_height}	#{pane_current_path}' | sort)
exp0=$(printf '%s\n' "$expected" | awk -F'\t' '$1 == 0 {print $1"\t"$2"\t"$3"\t"$4}')
got0=$(printf '%s\n' "$got" | awk -F'\t' '$1 == 0')
[ "$exp0" = "$got0" ] && pass "w0 structure + PWDs identical" || { fail "w0 differs"; diff <(echo "$exp0") <(echo "$got0"); }
wait $WW 2>/dev/null
[ "$fails" = 0 ] || { echo "--- watch:"; cat "$SB/watch.log" | head -12; echo "--- dead panes:"; "$T" list-panes -t "$S" -F '#{pane_index} dead=#{pane_dead} exit=#{pane_dead_status}' 2>/dev/null; }
m=$(poll 40 "$T capture-pane -p -t $S:0.0 | grep -cE 'LIVE_MARKER_(ALPHA|BETA)'")
[ -n "$m" ] && pass "nvim pane restored with buffers" || fail "nvim restore missing marker"
r2=$(poll 150 "$T capture-pane -p -t $S:0.1 | grep -c papaya")
[ -n "$r2" ] && pass "pi pane resumed conversation (papaya)" || fail "pi resume missing papaya"
n=$("$T" capture-pane -p -t "$S":0.2 | grep -c "was running sleep")
[ "$n" -ge 1 ] && pass "note echoed" || fail "note missing"

### cleanup: session + isolated state
"$T" kill-session -t "=$S" 2>/dev/null || true
rm -rf "$SB" "$PROJ"
echo
[ "$fails" = 0 ] && echo "LIVE ALL GREEN" || echo "$fails LIVE FAILURES"
exit "$fails"
