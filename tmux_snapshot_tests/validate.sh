#!/bin/bash
# Headless validation of snapshot.sh/restore.sh on a private tmux socket.
# Builds complex sessions (scratch panes, spaces-in-dirs, zoom, notes,
# allowlist relaunch, pi registry, hooks-during-restore), saves, kills the
# server, restores, and structurally compares. Exits nonzero on any failure.
set -u
#!/bin/bash
# Integration tests for snapshot.sh/restore.sh on an isolated tmux server
# (private socket blithe_val). Scripts under test default to the repo's
# scripts/ (~/bin symlinks); override with SRC=/path. Usage: ./validate.sh
here="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$(git -C "$here" rev-parse --show-toplevel)/scripts}"
export TMUX_BIN="$here/bin/tmux"
export XDG_STATE_HOME="$here/state"
export XDG_CONFIG_HOME="$here/xdgconf"
export SHELL=/bin/sh
export PATH="$here/shim/bin:$PATH"
# simulate in-tmux execution (hooks/keybinds): scripts must not clobber this
export TMUX="/tmp/tmux-$(id -u)/blithe_val,99999,0"
TMUX="$TMUX_BIN"
export PI_SESSION_DIR="$here/pi_sessions"
fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }

rm -rf "$here/state" "$here/xdgconf"
mkdir -p "$here/state" "$here/xdgconf/tmux" "$here/shim/bin" "$here/pi_sessions" /tmp/bb/a /tmp/bb/b "/tmp/bb/d e"
# fake pi: records argv (basename must be "pi" for snapshot's process walk)
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$(dirname "$0")/../shim_calls"\nsleep 30\n' > "$here/shim/bin/pi"
chmod +x "$here/shim/bin/pi"
: > "$here/shim/shim_calls"

# kill-server returns before the socket is unlinked; racing it spawns
# sessions on a dying server (tmux 3.7c)
kill_server() {
    "$TMUX" kill-server 2>/dev/null
    sock="/tmp/tmux-$(id -u)/blithe_val"
    i=0
    while [ -e "$sock" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
    rm -f "$sock"
}
kill_session() {
    "$TMUX" kill-session -t "$1" 2>/dev/null
    i=0
    while "$TMUX" has-session -t "=$1" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
}
ident_of() { echo "$(cut -c1-8 /proc/sys/kernel/random/boot_id):$("$TMUX" display-message -p '#{pid}')"; }

# normalized structural dump: scratch-filtered, geometry+path+active per pane
# fields: sess|wi|pidx|wname|wactive|left,top,WxH|pactive|path|zoom
dump() {
    "$TMUX" list-panes -a -F '#{session_name}	#{window_index}	#{window_name}	#{window_active}	#{pane_left},#{pane_top},#{pane_width}x#{pane_height}	#{pane_index}	#{pane_active}	#{pane_current_path}	#{window_zoomed_flag}	#{@scratch}	#{@park}' |
    awk -F'\t' '$10 == "1" || $11 == "1" { next }
        { print $1 "|" $2 "|" $6 "|" $3 "|" $4 "|" $5 "|" $7 "|" $8 "|" $9 }' | sort
}

kill_server

### build alpha: 3 windows; w0 4 panes odd sizes + spaces-dir; w1 2 panes zoomed; w2 sleep program
"$TMUX" new-session -d -x 200 -y 50 -s alpha -n code -c /tmp/bb/a
"$TMUX" split-window -h -t alpha:0 -c /tmp/bb/a
"$TMUX" split-window -v -t alpha:0.1 -c "/tmp/bb/d e"
"$TMUX" split-window -v -t alpha:0.0 -c "$here"
"$TMUX" resize-pane -t alpha:0.0 -x 60
"$TMUX" resize-pane -t alpha:0.2 -y 12
"$TMUX" select-pane -t alpha:0.3
"$TMUX" new-window -d -t alpha:1 -n build -c /tmp/bb/b
"$TMUX" split-window -h -t alpha:1 -c /tmp/bb/b
"$TMUX" select-pane -t alpha:1.1
"$TMUX" new-window -d -t alpha:2 -n misc -c /tmp/bb/b
"$TMUX" send-keys -t alpha:2 'sleep 987' Enter
sleep 0.4
"$TMUX" resize-pane -Z -t alpha:1
"$TMUX" select-window -t alpha:1

### build beta: hidden scratch window (alone) + shown scratch pane inside w1
"$TMUX" new-session -d -x 200 -y 50 -s beta -n term -c /tmp/bb/a
"$TMUX" set-option -p -t beta:0.0 @scratch 1
"$TMUX" new-window -d -t beta:1 -n work -c /tmp/bb/a
"$TMUX" split-window -h -t beta:1 -c /tmp/bb/b
"$TMUX" set-option -p -t beta:1.1 @scratch 1

sleep 0.5   # let sleep 987 register as pane command
expected_alpha=$(dump | awk -F'|' '$1 == "alpha"')
expected_beta_nonzoom=$(dump | awk -F'|' '$1 == "beta"')

# dropping a session's active window (scratch-only) makes its first survivor active;
# likewise a dropped active pane makes the first surviving pane active
fixup_active() {
    awk -F'|' -v OFS='|' '
    { n++; line[n]=$0; sess[n]=$1; win[n]=$1 "|" $2
      if (!(win[n] in firstr)) firstr[win[n]]=n
      if ($5=="1") act[sess[n]]=1
      if ($7=="1") pact[win[n]]=1 }
    END { for (r=1; r<=n; r++) { split(line[r], f, "|")
        if (!act[sess[r]] && firstr[win[r]]==r) f[5]=1
        if (!pact[win[r]] && firstr[win[r]]==r) f[7]=1
        out=f[1]; for (i=2; i<=9; i++) out=out "|" f[i]; print out } }'
}
expected_alpha=$(printf '%s\n' "$expected_alpha" | fixup_active)
expected_beta_nonzoom=$(printf '%s\n' "$expected_beta_nonzoom" | fixup_active)

### parking session (excluded wholesale) + a session hosting a @park pane
"$TMUX" new-session -d -x 100 -y 30 -s tmux_scratch_pane_parking -n hold -c /tmp/bb/a
"$TMUX" set-option -p -t tmux_scratch_pane_parking:0.0 @park 1
"$TMUX" new-session -d -x 150 -y 40 -s parked -n main -c /tmp/bb/a
"$TMUX" split-window -h -t parked:0 -c /tmp/bb/b
"$TMUX" new-window -d -t parked:1 -n host -c /tmp/bb/a
"$TMUX" split-window -h -t parked:1 -c /tmp/bb/b
"$TMUX" set-option -p -t parked:1.1 @park 1
sleep 0.3
expected_parked_nonzoom=$(dump | awk -F'|' '$1 == "parked"')
expected_parked_nonzoom=$(printf '%s\n' "$expected_parked_nonzoom" | fixup_active)
env -u TMUX "$SRC/snapshot.sh" --all
[ ! -e "$here/state/tmux/tmux_scratch_pane_parking.tsv" ] && pass "--all skips parking session" || fail "--all snapshotted parking session"
[ -f "$here/state/tmux/parked.tsv" ] && pass "--all wrote parked.tsv" || fail "parked.tsv missing"
awk -F'\t' '$1 == "p" && $2 == 0 { n++ } END { exit !(n == 2) }' "$here/state/tmux/parked.tsv" && pass "parked w0 intact" || fail "parked w0 pane count"
awk -F'\t' '$1 == "p" && $2 == 1 { n++ } END { exit !(n == 1) }' "$here/state/tmux/parked.tsv" && pass "@park pane dropped from hosting window" || fail "parked w1 pane count"
awk -F'\t' '$1 == "w" && $5 == "host" { exit !($6 == "-") }' "$here/state/tmux/parked.tsv" && pass "@park window layout marked -" || fail "host layout should be -"
env -u TMUX "$SRC/snapshot.sh" tmux_scratch_pane_parking 2>/dev/null && fail "explicit parking snapshot should fail" || pass "explicit parking snapshot refused"
# marker hygiene: stale bypasses + heals, fresh blocks
touch -d '10 minutes ago' "$here/state/tmux/.restoring"
env -u TMUX "$SRC/snapshot.sh" parked >/dev/null 2>&1 && pass "stale .restoring bypassed" || fail "stale marker blocked snapshot"
[ ! -e "$here/state/tmux/.restoring" ] && pass "stale marker removed" || fail "stale marker lingers"
touch "$here/state/tmux/.restoring"
before=$(stat -c %Y "$here/state/tmux/parked.tsv"); sleep 1.1
env -u TMUX "$SRC/snapshot.sh" parked && pass "fresh marker no-ops snapshot" || fail "fresh marker errored"
[ "$(stat -c %Y "$here/state/tmux/parked.tsv")" = "$before" ] && pass "fresh marker: nothing written" || fail "snapshot ran despite marker"
rm -f "$here/state/tmux/.restoring"

### structural hooks fire snapshot.sh during restore (self-corruption guard test)
"$TMUX" set-hook -g after-new-window   "run-shell -b 'env TMUX_BIN=$TMUX_BIN XDG_STATE_HOME=$XDG_STATE_HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME $here/snapshot.sh'"
"$TMUX" set-hook -g after-split-window "run-shell -b 'env TMUX_BIN=$TMUX_BIN XDG_STATE_HOME=$XDG_STATE_HOME XDG_CONFIG_HOME=$XDG_CONFIG_HOME $here/snapshot.sh'"

### save, kill, restore
"$SRC/snapshot.sh" alpha && "$SRC/snapshot.sh" beta || fail "snapshot.sh exited nonzero"
[ -f "$here/state/tmux/alpha.tsv" ] && pass "alpha.tsv written" || fail "alpha.tsv missing"
[ -f "$here/state/tmux/beta.tsv" ] && pass "beta.tsv written" || fail "beta.tsv missing"

awk -F'\t' '$1 == "p" { n++ } END { exit !(n == 7) }' "$here/state/tmux/alpha.tsv" && pass "alpha 7 pane rows" || fail "alpha pane row count"
awk -F'\t' '$1 == "p" { n++ } END { exit !(n == 1) }' "$here/state/tmux/beta.tsv" && pass "beta 1 pane row (hidden scratch window + shown scratch pane dropped)" || fail "beta pane row count"
awk -F'\t' '$1 == "w" && $5 == "work" { exit !($6 == "-") }' "$here/state/tmux/beta.tsv" && pass "scratch-hosting window layout marked -" || fail "work window layout should be -"
grep -q "sleep" "$here/state/tmux/alpha.tsv" && pass "program recorded" || fail "sleep not recorded"

alpha_before=$(cat "$here/state/tmux/alpha.tsv")
kill_server
env -u TMUX "$SRC/restore.sh" alpha || fail "restore alpha exited nonzero"
env -u TMUX "$SRC/restore.sh" beta || fail "restore beta exited nonzero"
env -u TMUX "$SRC/restore.sh" parked || fail "restore parked exited nonzero"
sleep 1
[ "$alpha_before" = "$(cat "$here/state/tmux/alpha.tsv")" ] && pass "hooks did not corrupt alpha.tsv during restore" || fail "alpha.tsv changed during restore"
[ ! -e "$here/state/tmux/blithe-idburn.tsv" ] && pass "id-burner never snapshotted" || fail "blithe-idburn.tsv exists"
[ ! -e "$here/state/tmux/.restoring" ] && pass ".restoring marker cleaned up" || fail ".restoring marker lingers"
"$TMUX" set-hook -gu after-new-window
"$TMUX" set-hook -gu after-split-window

### structural comparison
got_alpha=$(dump | awk -F'|' '$1 == "alpha"')
if [ "$expected_alpha" = "$got_alpha" ]; then pass "alpha structure identical"; else
    fail "alpha structure differs"; diff <(echo "$expected_alpha") <(echo "$got_alpha"); fi

# beta: layout approximated ("-" -> tiled), compare names/paths/active/count only
beta_norm() { awk -F'|' -v s="$1" '$1 == s { print $1 "|" $2 "|" $4 "|" $5 "|" $7 "|" $8 "|" $9 }'; }
if [ "$(echo "$expected_beta_nonzoom" | beta_norm beta)" = "$(dump | beta_norm beta)" ]; then
    pass "beta structure identical (minus approximated layout)"; else
    fail "beta structure differs"; diff <(echo "$expected_beta_nonzoom" | beta_norm beta) <(dump | beta_norm beta); fi

parked_norm() { awk -F'|' -v s="$1" '$1 == s { print $1 "|" $2 "|" $4 "|" $5 "|" $7 "|" $8 "|" $9 }'; }
if [ "$(echo "$expected_parked_nonzoom" | parked_norm parked)" = "$(dump | parked_norm parked)" ]; then
    pass "parked structure identical (minus approximated layout)"; else
    fail "parked structure differs"; diff <(echo "$expected_parked_nonzoom" | parked_norm parked) <(dump | parked_norm parked); fi

### misc pane got the note; sleep pane back as shell
note=$("$TMUX" capture-pane -p -t alpha:2 | grep -c "This pane was running sleep")
[ "$note" -ge 1 ] && pass "was-running note present" || fail "note missing"
curcmd=$("$TMUX" display-message -p -t alpha:2.0 '#{pane_current_command}')
[ "$curcmd" = "sh" ] && pass "non-allowlisted pane restored as shell" || fail "misc pane runs $curcmd"

### zoom survived
z=$("$TMUX" display-message -p -t alpha:1 '#{window_zoomed_flag}')
[ "$z" = "1" ] && pass "zoom restored" || fail "zoom lost"
wa=$("$TMUX" display-message -p -t alpha '#{window_index}')
[ "$wa" = "1" ] && pass "active window restored" || fail "active window is $wa"

### existing session: second restore is a clean no-op
out=$(env -u TMUX "$SRC/restore.sh" alpha 2>&1) && fail "second restore should error" || case "$out" in *"already exists"*) pass "second restore errors (session exists)" ;; *) fail "second restore: $out" ;; esac
out=$("$SRC/restore.sh" alpha 2>&1) && fail "restore inside tmux should error" || case "$out" in *"outside tmux"*) pass "restore inside tmux refused" ;; *) fail "in-tmux restore: $out" ;; esac

### allowlist relaunch: gamma with an allowlisted, bare-launch-survivable program
printf 'cat\n' > "$here/xdgconf/tmux/programs"
"$TMUX" new-session -d -x 120 -y 30 -s gamma -n g -c /tmp/bb/a
"$TMUX" send-keys -t gamma:0 'cat' Enter
sleep 0.4

### pi registry: snapshot-time join marks pi:<uuid>; restore resumes it
uuid="2026-10-19T00-00-00-000Z_deadbeef-0000-7000-8000-000000000000"
: > "$here/pi_sessions/$uuid.jsonl"
"$TMUX" new-session -d -x 120 -y 30 -s zeta -n z -c /tmp/bb/a
"$TMUX" send-keys -t zeta:0 'pi' Enter
sleep 0.4
zpane=$("$TMUX" display-message -p -t zeta:0 '#{pane_id}')
gp=$("$TMUX" display-message -p -t gamma:0 '#{pane_id}')
printf '%s\t%s\t%s\n%s\t%s\t%s\n' "$(ident_of)" "$zpane" "$uuid.jsonl" "$(ident_of)" "$gp" "$uuid.jsonl" > "$here/state/tmux/pi_registry"
"$SRC/snapshot.sh" zeta
grep -q "pi:$uuid" "$here/state/tmux/zeta.tsv" && pass "registry joined at snapshot (pi:<uuid> recorded)" || fail "pi:<uuid> missing from zeta.tsv"

"$SRC/snapshot.sh" gamma
grep -q "pi:$uuid" "$here/state/tmux/gamma.tsv" && fail "registry row hijacked non-pi (cat) pane" || pass "non-pi pane never joins registry"
kill_session gamma
rm -f "$here/shim/shim_calls"
env -u TMUX "$SRC/restore.sh" gamma
sleep 0.5
c=$("$TMUX" display-message -p -t gamma:0.0 '#{pane_current_command}')
[ "$c" = "cat" ] && pass "allowlisted program relaunched" || fail "gamma pane runs $c"
gnote=$("$TMUX" capture-pane -p -t gamma:0 | grep -c "was running")
[ "$gnote" = 0 ] && pass "no note typed into relaunched program" || fail "note leaked into relaunched pane"

### eta: node panes (npm run dev etc.) must NOT relaunch as pi — plain shell
sed "s/\tcat\t/\tnode\t/" "$here/state/tmux/gamma.tsv" > "$here/state/tmux/eta.tsv"
: > "$here/shim/shim_calls"
env -u TMUX "$SRC/restore.sh" eta
sleep 1
c=$("$TMUX" display-message -p -t eta:0.0 '#{pane_current_command}')
n=$("$TMUX" capture-pane -p -t eta:0.0 | grep -c "was running node")
[ "$c" = "sh" ] && [ "$n" -ge 1 ] && pass "node pane restores as shell + note (never pi)" || fail "eta: cmd=$c note=$n"

### delta: pi:<uuid> restore resumes the session via shim
sed "s/\tnode\t/\tpi:$uuid\t/" "$here/state/tmux/eta.tsv" > "$here/state/tmux/delta.tsv"
: > "$here/shim/shim_calls"
env -u TMUX "$SRC/restore.sh" delta
sleep 0.5
grep -q -- "--session $uuid" "$here/shim/shim_calls" 2>/dev/null && pass "pi session resumed by uuid" || fail "pi resume args: $(cat "$here/shim/shim_calls" 2>/dev/null)"

### concurrent saves
( "$SRC/snapshot.sh" alpha 2>"$here/c1.err"; echo $? > "$here/c1.rc" ) &
( "$SRC/snapshot.sh" alpha 2>"$here/c2.err"; echo $? > "$here/c2.rc" ) &
wait
[ "$(cat "$here/c1.rc")" = 0 ] && [ "$(cat "$here/c2.rc")" = 0 ] && pass "concurrent saves exit 0" || fail "concurrent saves rc: $(cat "$here/c1.rc")/$(cat "$here/c2.rc")"
awk -F'\t' '$1 == "s" { n++ } END { exit !(n >= 1) }' "$here/state/tmux/alpha.tsv" && pass "snapshot file valid after concurrent save" || fail "alpha.tsv corrupt"

### missing dir falls back to HOME (sleep row neutralized: dir-fallback is the subject)
sed -e 's|/tmp/bb/a|/tmp/bb/gone|' -e 's/\tsleep\t/\tsh\t/' "$here/state/tmux/alpha.tsv" > "$here/state/tmux/epsilon.tsv"
env -u TMUX "$SRC/restore.sh" epsilon && pass "missing-dir restore exits 0" || fail "missing-dir restore failed"
p0=$("$TMUX" display-message -p -t epsilon:0.0 '#{pane_current_path}')
[ "$p0" = "$HOME" ] && pass "missing dir fell back to \$HOME" || fail "epsilon pane at $p0"

### re-snapshot overwrites (session name = key)
before=$(stat -c %Y "$here/state/tmux/alpha.tsv")
sleep 1.1
"$SRC/snapshot.sh" alpha && [ "$(stat -c %Y "$here/state/tmux/alpha.tsv")" -gt "$before" ] && pass "re-snapshot overwrites same file" || fail "re-snapshot did not overwrite"

kill_server
"$TMUX" new-session -d -s tmux_scratch_pane_parking -n hold -c /tmp
out=$(env -u TMUX "$SRC/snapshot.sh" --all 2>&1) && case "$out" in *"no sessions to snapshot"*) pass "--all with only parking session no-ops" ;; *) fail "--all parking-only: $out" ;; esac || fail "--all parking-only exited nonzero"
[ ! -e "$here/state/tmux/tmux_scratch_pane_parking.tsv" ] && pass "parking-only --all wrote nothing" || fail "parking tsv written"
kill_server
echo
[ "$fails" = 0 ] && echo "ALL GREEN" || echo "$fails FAILURES"
exit "$fails"
