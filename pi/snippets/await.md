Block until another agent signals it is safe to continue: one bash call that reads a named pipe, then carry on with whatever follows. While it runs, do nothing else — no polling, no checking on the other agent, no other tool calls.

```bash
name=<name>
pipe="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-signals/$name.fifo"
mkdir -p "$(dirname "$pipe")"
[ -p "$pipe" ] || mkfifo "$pipe"
timeout "${AWAIT_TIMEOUT_S:-1800}" bash -c '
    exec 3<>"$1"  # O_RDWR: read() blocks instead of hitting EOF while no writer exists
    IFS= read -r signal <&3
    printf "signal received: %s\n" "$signal"
' bash "$pipe"
```

- Don't run the bash cmd with a tool-call timeout — the call must be free to block as long as it takes; the inner `timeout` (`AWAIT_TIMEOUT_S`, default 1800 s) bounds the wait itself.
- Exit 0 → signal received; continue.
- Exit 124 → timed out: stop and tell me. Do not assume the other agent finished; do not retry on your own.
- One waiter per pipe — concurrent readers steal each other's signal.

Pipe name (substitute for `<name>` in the command above):
