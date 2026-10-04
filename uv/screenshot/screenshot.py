#!/usr/bin/env python3
"""screenshot — capture window/region/monitor to the clipboard.

Three modes, driven by invocation pattern (matches the old sh script):
  1st run:   hacksaw box-select; a click (no drag) selects the window
  2nd run
  within 2s: whole capture of the monitor containing the pointer
  --own:     internal mode — resident Qt clipboard owner, forked off after
             a capture so the parent can exit immediately

X11: the owner child serves the raw PNG via Qt (correct INCR for any size;
xclip 0.13 serves nothing over ~1MB and Electron apps refuse to read
xclip-owned selections at all — signalapp/Signal-Desktop#6554).
Wayland: grim/slurp/wl-copy, no owner child needed.
"""

from __future__ import annotations

import getpass
import os
import subprocess
import sys
from pathlib import Path

DOTFILES = Path(os.environ.get("dotfiles", Path.home() / "source/dotfiles"))
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles"
LOCKFILE = Path(f"/tmp/screenshot-{getpass.getuser()}.lock")
SOUND_FILE = DOTFILES / "media/camera.ogg"

MIME_ALIASES = {
    "image/png": ["image/png", "image/x-png"],
    "text/plain": ["text/plain", "text/plain;charset=utf-8", "UTF8_STRING", "STRING", "TEXT"],
}


def notify(msg: str) -> None:
    subprocess.run(["notify-send", "-t", "1000", msg], check=False)


def play_shutter() -> None:
    if SOUND_FILE.exists():
        subprocess.Popen(
            ["ffplay", "-nodisp", "-autoexit", str(SOUND_FILE)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )


def is_wayland() -> bool:
    return bool(os.environ.get("WAYLAND_DISPLAY"))


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


# ---------------------------------------------------------------- capture

def capture_region_or_window(png_path: Path) -> bool:
    """hacksaw: drag = region, click = window. False if the user aborted."""
    sel = run(["hacksaw", "-f", "%i %g"]).stdout.strip()
    if not sel:
        return False
    win_id, geometry = sel.split(" ", 1)
    with png_path.open("wb") as fh:
        subprocess.run(["shotgun", "-i", win_id, "-g", geometry, "-"], stdout=fh, check=False)
    return png_path.stat().st_size > 0


def pointer_monitor_geometry() -> str | None:
    """Geometry (WxH+X+Y) of the RandR output containing the pointer."""
    loc = run(["xdotool", "getmouselocation", "--shell"]).stdout
    pos = dict(
        line.split("=", 1) for line in loc.strip().splitlines() if "=" in line
    )
    if "X" not in pos or "Y" not in pos:
        return None
    px, py = int(pos["X"]), int(pos["Y"])

    for field in run(["xrandr", "--query"]).stdout.splitlines():
        if " connected" not in field:
            continue
        for tok in field.split():
            parts = tok.split("+")
            dims = parts[0].split("x")
            if len(parts) != 3 or len(dims) != 2 or not dims[0].isdigit():
                continue
            w, h, x, y = *map(int, dims), int(parts[1]), int(parts[2])
            if x <= px < x + w and y <= py < y + h:
                return f"{w}x{h}+{x}+{y}"
    return None


def capture_pointer_monitor(png_path: Path) -> bool:
    geom = pointer_monitor_geometry()
    if not geom:
        return False
    with png_path.open("wb") as fh:
        subprocess.run(["shotgun", "-g", geom, "-"], stdout=fh, check=False)
    return png_path.stat().st_size > 0


def capture_wayland(png_path: Path, whole: bool) -> None:
    cmd = ["grim", "-"] if whole else ["grim", "-g", subprocess.run(
        ["slurp"], capture_output=True, text=True).stdout.strip(), "-"]
    with png_path.open("wb") as fh:
        subprocess.run(cmd, stdout=fh, check=False)
    subprocess.run(
        ["wl-copy", "--type", "image/png"],
        stdin=png_path.open("rb"), check=False,
    )


# ---------------------------------------------------------- clipboard owner

def spawn_owner(png_path: Path) -> None:
    """Replace any previous owner, then detach a fresh one."""
    subprocess.run(["pkill", "-f", "screenshot.py --own"], check=False)
    subprocess.Popen(
        [sys.executable, __file__, "--own", "image/png", str(png_path)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def own_mode(mime: str, source: Path) -> int:
    try:
        from PyQt6.QtCore import QMimeData, QByteArray
        from PyQt6.QtGui import QClipboard
        from PyQt6.QtWidgets import QApplication
    except ImportError:
        print("screenshot --own: PyQt6 not available", file=sys.stderr)
        return 1

    data = source.read_bytes()  # also accepts /dev/stdin-style paths
    if not data:
        return 1

    app = QApplication([])
    md = QMimeData()
    raw = QByteArray(data)
    md.setData(mime, raw)
    for alias in MIME_ALIASES.get(mime, []):
        md.setData(alias, raw)

    clip = QApplication.clipboard()
    clip.setMimeData(md, QClipboard.Mode.Clipboard)
    clip.setMimeData(md, QClipboard.Mode.Selection)

    # the first dataChanged is our own setMimeData; any later one means
    # another app owns the clipboard now — quit so owners don't accumulate
    import itertools
    emissions = itertools.count()
    clip.dataChanged.connect(lambda: next(emissions) and app.quit())
    return app.exec()


# ------------------------------------------------------------------- main

def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--own":
        return own_mode(sys.argv[2], Path(sys.argv[3] if len(sys.argv) > 3 else "/dev/stdin"))
    if not SOUND_FILE.exists():
        notify("Camera sound file not found")
        return 1

    # detach from the launching keybind daemon's session, like the old
    # `setsid "$0" selfexec` hop
    try:
        os.setsid()
    except OSError:
        pass

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    png_path = CACHE_DIR / "screenshot.png"

    whole = False
    if LOCKFILE.exists():
        try:
            os.killpg(int(LOCKFILE.read_text().strip()), 15)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
        LOCKFILE.unlink(missing_ok=True)
        whole = True
    else:
        # marks "selection in progress": a second invocation during hacksaw
        # reads this and captures the whole pointer monitor instead
        LOCKFILE.write_text(str(os.getpid()))

    if is_wayland():
        capture_wayland(png_path, whole)
        LOCKFILE.unlink(missing_ok=True)
        play_shutter()
        notify("Screenshot Taken 📸")
        return 0

    ok = capture_pointer_monitor(png_path) if whole else capture_region_or_window(png_path)
    LOCKFILE.unlink(missing_ok=True)
    if not ok:
        return 1

    spawn_owner(png_path)
    play_shutter()
    notify("Screenshot Taken 📸")
    return 0


if __name__ == "__main__":
    sys.exit(main())
