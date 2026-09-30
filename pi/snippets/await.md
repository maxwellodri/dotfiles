Block until another agent signals it is safe to continue: run the await once, then carry on with whatever follows. While it runs, do nothing else — no polling, no checking on the other agent, no other tool calls.

```bash
await_pipe <name>
```

- Invoke the bash tool with **no `timeout` parameter** — omit it entirely; an omitted timeout is the only truly unbounded wait, and this wait is unbounded by design. Never encode "no timeout" as a large number: the tool rejects anything above 2147483.647 s, and any explicit timeout would cut the wait short.
- Exit 0 → signal received; continue. If the trigger fired earlier, the return is instant.
- An aborted/killed call means the wait was cut short: stop and tell me. Do not assume the other agent finished; do not retry on your own.

Signal name (substitute for `<name>` in the command above):
