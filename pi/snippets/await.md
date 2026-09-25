Block until another agent signals it is safe to continue: one bash call that waits for the latched signal, then carry on with whatever follows. While it runs, do nothing else — no polling, no checking on the other agent, no other tool calls.

```bash
flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-signals/<name>.signaled"
mkdir -p "$(dirname "$flag")"
timeout "${AWAIT_TIMEOUT_S:-1800}" bash -c '
    until mv "$1" "$1.claimed.$$" 2>/dev/null; do  # mv = atomic claim, only one await consumes the latch
        sleep 0.1
    done
    rm -f "$1.claimed.$$"
    echo "signal received"
' bash "$flag"
```

- Don't run the bash cmd with a tool-call timeout — the call must be free to block as long as it takes; the inner `timeout` (`AWAIT_TIMEOUT_S`, default 1800 s) bounds the wait itself.
- Exit 0 → signal received; continue. If the trigger fired before this call, the return is instant.
- Exit 124 → timed out: stop and tell me. Do not assume the other agent finished; do not retry on your own.
- One waiter per name — the latch is consumed by a single await.

Signal name (substitute for `<name>` in the command above):
