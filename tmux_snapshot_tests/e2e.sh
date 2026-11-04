#!/bin/bash
# Fully-live e2e, fully sandboxed: real zsh panes, real pi (wrapper + model),
# real nvim (live config incl. snapshot_nvim.lua), real scratch/parking
# semantics — ALL state under .scratch/e2e/state. The real ~/.local/state is
# never touched: interactive zsh re-sets XDG_STATE_HOME via zshrc, so every
# program launch in a build pane carries an explicit env prefix; restored
# panes run non-interactive (-c) shells and inherit the server env instead.
# Cleanup only ever rm -rf's the sandbox.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
sandbox="$here/e2e-sandbox"
mkdir -p "$sandbox/bin"
printf '#!/bin/sh\nexec /usr/bin/env -u TMUX_BIN tmux -L blithe_e2e "$@"\n' > "$sandbox/bin/tmux"
chmod +x "$sandbox/bin/tmux"
export TMUX_BIN="$sandbox/bin/tmux"   # wrapper: exec tmux -L blithe_e2e
export XDG_STATE_HOME="$sandbox/state"
T="$TMUX_BIN"
X="XDG_STATE_HOME=$sandbox/state"
fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }
poll() { # poll <secs> <shell-cmd> — success when the pipeline outputs non-empty
    local secs=$1 i=0 out
    shift
    while [ "$i" -lt "$secs" ]; do
        out=$(sh -c "$*" 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return 0; }
        sleep 1; i=$((i + 1))
    done
    return 1
}
kill_server() {
    "$T" kill-server 2>/dev/null
    local sock="/tmp/tmux-$(id -u)/blithe_e2e" i=0
    while [ -e "$sock" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i+1)); done
    rm -f "$sock"
}
wait_server() { # a live server with the e2e session answers
    poll 30 "$T has-session -t =e2e 2>/dev/null && echo up"
}
realstore_leaks() { # jsonl files whose recorded cwd is the e2e dir
    for f in ~/.local/state/pi/sessions/*.jsonl; do
        [ -e "$f" ] || continue
        head -c 1500 "$f" | grep -q '"cwd":"/tmp/e2e' && basename "$f"
    done
}

# sandbox layout: the pi session dir must be a symlink (the wrapper enforces
# that invariant on PI_CODING_AGENT_SESSION_DIR wherever it points)
rm -rf "$sandbox/state" "$sandbox/pi-sessions" /tmp/e2e
mkdir -p "$sandbox/state/tmux" "$sandbox/state/pi" "$sandbox/pi-sessions" /tmp/e2e/proj
ln -s "$sandbox/pi-sessions" "$sandbox/state/pi/sessions"
ln -s "$sandbox/pi-sessions" "$sandbox/state/pi/archived_sessions"
printf 'E2E_MARKER_ALPHA line one\n' > /tmp/e2e/proj/e2e_a.txt
printf 'E2E_MARKER_BETA line two\n' > /tmp/e2e/proj/e2e_b.txt

leaks_before=$(realstore_leaks)
kill_server

### build: w0 dev (nvim/pi/sleep, odd geometry), w1 hosts the shown scratch
SHELL=/bin/zsh "$T" new-session -d -x 220 -y 55 -s e2e -n dev -c /tmp/e2e/proj
# restored panes (non-interactive shells) inherit the sandbox from here
"$T" set-environment -g XDG_STATE_HOME "$sandbox/state"
"$T" split-window -h -t e2e:0 -c /tmp/e2e/proj
"$T" split-window -v -t e2e:0.0 -c /tmp/e2e/proj
"$T" resize-pane -t e2e:0.0 -x 70
"$T" resize-pane -t e2e:0.1 -y 15
"$T" select-pane -t e2e:0.2
"$T" new-window -d -t e2e:1 -n scratchhost -c /tmp/e2e/proj
"$T" split-window -h -t e2e:1 -c /tmp/e2e/proj
"$T" set-option -p -t e2e:1.1 @scratch 1
"$T" set-option -p -t e2e:1.1 @scratch-origin "$("$T" display-message -p -t e2e '#{session_id}')"
"$T" select-pane -t e2e:1.0

### parking session, exactly like _tmux_scratch's park_session_ensure
"$T" new-session -d -s tmux_scratch_pane_parking 'exec sleep infinity'
"$T" set-option -t tmux_scratch_pane_parking @park 1

### p0: nvim — bare + :e (autosave must not need a clean quit), then reopen
"$T" send-keys -t e2e:0.0 "$X nvim" Enter
poll 30 "$T capture-pane -p -t e2e:0.0 | grep -c NORMAL" || fail "nvim UI never became ready"
"$T" send-keys -t e2e:0.0 ':e e2e_a.txt' Enter
poll 15 "$T capture-pane -p -t e2e:0.0 | grep -cE 'E2E_MARKER_(ALPHA|BETA)'"  || true
"$T" send-keys -t e2e:0.0 ':e e2e_b.txt' Enter
poll 15 "$T capture-pane -p -t e2e:0.0 | grep -c E2E_MARKER_BETA" || true
n=$(poll 25 "$T capture-pane -p -t e2e:0.0 | grep -cE 'E2E_MARKER_(ALPHA|BETA)'" )
[ -n "$n" ] && pass "nvim: files opened" || fail "nvim never showed files"
sha=$(python3 -c "import hashlib;print(hashlib.sha256(b'/tmp/e2e/proj').hexdigest())")
[ -f "$sandbox/state/tmux/nvim/$sha.vim" ] && pass "nvim: session autosaved while running (no :q)" || fail "no autosaved session file"
"$T" send-keys -t e2e:0.0 ':qa' Enter
poll 15 "$T display-message -p -t e2e:0.0 '#{pane_current_command}' | grep -c zsh" || true
"$T" send-keys -t e2e:0.0 "$X nvim" Enter
poll 30 "$T capture-pane -p -t e2e:0.0 | grep -c NORMAL" || true
m=$(poll 25 "$T capture-pane -p -t e2e:0.0 | grep -cE 'E2E_MARKER_(ALPHA|BETA)'" )
[ -n "$m" ] && pass "nvim: bare reopen shows buffers" || { fail "nvim reopen missing marker"; "$T" capture-pane -p -t e2e:0.0 | grep -v '^$' | head -6 > "$sandbox/reopen.dump"; grep -c "e2e_" "$sandbox/state/tmux/nvim/$sha.vim" >> "$sandbox/reopen.dump" 2>/dev/null; }

### p1: real pi via wrapper (registry row live, session in sandbox)
"$T" send-keys -t e2e:0.1 "$X pi" Enter
if ! poll 60 "$T capture-pane -p -t e2e:0.1 | grep -c 'MCP:'"; then
    fail "pi UI never became ready"
    "$T" capture-pane -p -t e2e:0.1 | grep -v '^$' | tail -4
fi
"$T" send-keys -t e2e:0.1 'reply with just: pineapple' Enter
r=$(poll 120 "$T capture-pane -p -t e2e:0.1 | grep -c pineapple")
[ -n "$r" ] && pass "pi: replied (conversation active)" || fail "pi never replied"
awk -F'\t' '$3 != ""' "$sandbox/state/tmux/pi_registry" 2>/dev/null | grep -q . && pass "pi wrapper wrote registry row" || fail "no registry row"
nsp=$(ls "$sandbox/pi-sessions/" 2>/dev/null | wc -l)
[ "$nsp" -ge 1 ] && pass "pi session landed in sandbox store" || fail "pi session not in sandbox"

### p2: a program that will become a note
"$T" send-keys -t e2e:0.2 'sleep 600' Enter
sleep 1

### snapshot --all
env -u TMUX ~/bin/snapshot.sh --all || fail "snapshot --all exited nonzero"
TSV="$sandbox/state/tmux/e2e.tsv"
[ -f "$TSV" ] && pass "e2e.tsv written (sandbox)" || fail "no e2e.tsv"
[ ! -e "$sandbox/state/tmux/tmux_scratch_pane_parking.tsv" ] && pass "parking session skipped" || fail "parking snapshotted"
awk -F'\t' '$1 == "p" && $2 == 0 { n++ } END { exit !(n == 3) }' "$TSV" && pass "w0 3 panes recorded" || fail "w0 pane count wrong"
awk -F'\t' '$1 == "p" && $2 == 1 { n++ } END { exit !(n == 1) }' "$TSV" && pass "w1 shown-scratch pane dropped" || fail "w1 pane count wrong"
awk -F'\t' '$1 == "w" && $2 == 1 { exit !($6 == "-") }' "$TSV" && pass "w1 layout marked -" || fail "w1 layout not -"
grep -q "pi:" "$TSV" && pass "pi:<uuid> recorded via registry" || fail "pi not recorded"
grep -q "	nvim	" "$TSV" && pass "nvim recorded" || fail "nvim not recorded"

### kill, restore, verify
dumpfmt='#{session_name}	#{window_index}	#{pane_index}	#{pane_left},#{pane_top},#{pane_width}x#{pane_height}	#{pane_current_path}	#{@scratch}'
expected=$("$T" list-panes -a -F "$dumpfmt" | awk -F'\t' '$1 == "e2e" && $6 != "1" {print}' | sort)
kill_server
env -u TMUX ~/bin/restore.sh e2e 2>"$sandbox/restore.err" || { fail "restore exited nonzero"; cat "$sandbox/restore.err"; }
wait_server || { fail "no server/session after restore"; cat "$sandbox/restore.err"; }
"$T" set-option -t e2e remain-on-exit on 2>/dev/null || true
( for i in $(seq 24); do echo "t=$((i / 2)): $($T list-windows -t e2e -F 'w#{window_index}:#{window_panes}p,dead=#{window_panes}d ' 2>/dev/null || echo GONE)"; sleep 0.5; done ) > "$sandbox/winwatch.log" &
WW=$!
sleep 8

got=$("$T" list-panes -a -F "$dumpfmt" | awk -F'\t' '$1 == "e2e" && $6 != "1" {print}' | sort); printf '%s\n' "$got" > "$sandbox/got.raw"
exp0=$(printf '%s\n' "$expected" | awk -F'\t' '$2 == 0')
got0=$(printf '%s\n' "$got" | awk -F'\t' '$2 == 0')
expw1=$(printf '%s\n' "$expected" | awk -F'\t' '$2 == 1 {print $1 "|" $5}' | sort)
gotw1=$(printf '%s\n' "$got" | awk -F'\t' '$2 == 1 {print $1 "|" $5}' | sort)
[ "$exp0" = "$got0" ] && pass "w0 structure + PWDs identical" || { fail "w0 structure differs"; diff <(echo "$exp0") <(echo "$got0"); }
[ "$expw1" = "$gotw1" ] && pass "w1 restored (panes/PWD; layout approximated by design)" || { fail "w1 differs"; diff <(echo "$expw1") <(echo "$gotw1") | tee "$sandbox/w1.diff"; }

m2=$(poll 40 "$T capture-pane -p -t e2e:0.0 | grep -cE 'E2E_MARKER_(ALPHA|BETA)'" )
[ -n "$m2" ] && pass "nvim pane: buffers auto-restored" || fail "nvim restore missing marker"
r2=$(poll 120 "$T capture-pane -p -t e2e:0.1 | grep -c pineapple")
[ -n "$r2" ] && pass "pi pane: conversation resumed (pineapple visible)" || fail "pi resume missing pineapple"
note=$("$T" capture-pane -p -t e2e:0.2 | grep -c "This pane was running sleep")
[ "$note" -ge 1 ] && pass "note echoed into zsh pane" || fail "note missing"
"$T" has-session -t "=tmux_scratch_pane_parking" 2>/dev/null && fail "parking session restored (should not be)" || pass "parking not restored"

wait $WW 2>/dev/null
[ "$expw1" = "$gotw1" ] || { echo "--- winwatch:"; cat "$sandbox/winwatch.log"; echo "--- w1 pane exit state:"; "$T" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} dead=#{pane_dead} cmd=#{pane_current_command}' 2>/dev/null | head -8; "$T" capture-pane -p -t e2e:1 2>/dev/null | grep -v '^$' | tail -3; }
leaks_after=$(realstore_leaks)
[ "$leaks_before" = "$leaks_after" ] && pass "real store untouched" || { fail "real store gained e2e sessions: $leaks_after"; }

### cleanup: sandbox only
kill_server
rm -rf "$sandbox/state" "$sandbox/pi-sessions" /tmp/e2e
echo
[ "$fails" = 0 ] && echo "E2E ALL GREEN" || echo "$fails E2E FAILURES"
exit "$fails"
