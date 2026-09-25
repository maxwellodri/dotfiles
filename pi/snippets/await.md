Block until another agent signals it is safe to continue: run the await once, then carry on with whatever follows. While it runs, do nothing else — no polling, no checking on the other agent, no other tool calls.

```bash
await_pipe <name>
```

- Run the bash command with **no timeout** — it must be free to block as long as the other agent takes; the wait is unbounded by design.
- Exit 0 → signal received; continue. If the trigger fired earlier, the return is instant.
- An aborted/killed call means the wait was cut short: stop and tell me. Do not assume the other agent finished; do not retry on your own.

Signal name (substitute for `<name>` in the command above):
