Tell a waiting agent that the work preceding this snippet is finished: one fire-and-forget latch write. Never blocks, never retries — run it once, after every instruction above this point is complete (and before starting anything below it).

```bash
flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-signals/<name>.signaled"
mkdir -p "$(dirname "$flag")"
date -u +%FT%TZ >"$flag"
echo "signaled $flag"
```

- Needs no listener: if nobody awaits yet, the latch stays and the next `$await` on the same name returns instantly.
- The waiting side consumes the latch on return; a later `$await` blocks until triggered again.

Signal name (substitute for `<name>` in the command above):
