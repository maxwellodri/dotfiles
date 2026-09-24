Tell a waiting agent that the work preceding this snippet is finished: one fire-and-forget write to a named pipe. Never blocks, never retries — run it once, after every instruction above this point is complete (and before starting anything below it).

```bash
python3 -c '
import os, sys

base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "agent-signals")
path = os.path.join(base, sys.argv[1] + ".fifo")
try:
    fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)  # ENXIO while no reader is attached
except OSError as e:
    print(f"signal dropped ({e.strerror}): nobody is waiting on {path}")
    sys.exit(0)  # fire-and-forget: dropped is a normal outcome, not an error
os.write(fd, b"done\n")
os.close(fd)
print(f"signaled {path}")
' <name>
```

- The open is non-blocking: with no reader attached it fails instantly and the signal is dropped — the correct outcome when nobody waits. Report `signal dropped ...` in one line and carry on.
- The waiting side (`$await`) creates and owns the pipe; this side never creates or removes it.

Pipe name (substitute for `<name>` in the command above):
