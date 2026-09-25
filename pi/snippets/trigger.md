Tell a waiting agent that the work preceding this snippet is finished: run the latched fire-and-forget signal once. It never blocks and needs no listener — if nobody awaits yet, the latch stays and the next `await_pipe` on the same name returns instantly.

```bash
trigger_pipe <name>
```

Run it once, after every instruction above this point is complete (and before starting anything below it). Report the script's output in one line and carry on.

Signal name (substitute for `<name>` in the command above):
