#!/usr/bin/env python3
"""dwm status bar: async pollers feed shared state; renderer calls xsetroot on change.

Each data source polls on its own cadence so nothing blocks the 1s render loop.
Heavy commands (docker, wg, ping, checkupdates) run minutes apart, not per tick.
"""

from __future__ import annotations

import asyncio
import functools
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PACKAGE_FILE = SCRIPT_DIR / "package_file.txt"
PACKAGE_CACHE_SECONDS = 3600

INTERVALS = {
    "cpu": 5,
    "memory": 5,
    "reminders": 60,
    "internet": 30,
    "docker": 60,
    "wireguard": 5,
    "battery": 30,
    "packages": 3600,
    "keymap": 300,
    "render": 1,
}


def detect_tag() -> str:
    try:
        tag = (REPO_ROOT / ".dotfile_tag").read_text().strip()
        if tag:
            return tag
    except OSError:
        pass
    try:
        zprofile = (Path.home() / ".zprofile").read_text()
        match = re.search(r'export dotfiles_tag="(\w+)"', zprofile)
        if match:
            return match.group(1)
    except OSError:
        pass
    return ""


TAG = detect_tag()


async def run_cmd(args: list[str], timeout: float = 15) -> str | None:
    """Run a command, return stripped stdout, or None on any failure/timeout."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
    except (FileNotFoundError, PermissionError, OSError):
        return None
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return None
    if proc.returncode != 0:
        return None
    return stdout.decode(errors="replace").strip()


def poller(interval: int):
    """Decorate an async poller: run once immediately, then every interval.

    A failed run keeps the previous state instead of blanking the bar.
    """

    def wrap(func):
        async def run(state: dict):
            while True:
                try:
                    await func(state)
                except asyncio.CancelledError:
                    raise
                except Exception:
                    pass
                await asyncio.sleep(interval)

        return run

    return wrap


@poller(INTERVALS["cpu"])
async def poll_cpu(state: dict):
    stat_fields = Path("/proc/stat").read_text().splitlines()[0].split()
    # iowait counts as busy, matching the old dstatus.sh accounting
    fields = [int(x) for x in stat_fields[1:9]]
    total = sum(fields)
    idle = fields[3]
    previous = state.get("_cpu_previous")
    state["_cpu_previous"] = (total, idle)
    if previous is None:
        return
    diff_total = total - previous[0]
    diff_idle = idle - previous[1]
    usage = 0 if diff_total <= 0 else (diff_total - diff_idle) * 100 // diff_total
    state["cpu"] = max(0, min(100, usage))


@poller(INTERVALS["memory"])
async def poll_memory(state: dict):
    meminfo = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, value = line.partition(":")
        meminfo[key] = int(value.strip().split()[0])
    total = meminfo["MemTotal"]
    used = total - meminfo["MemAvailable"]
    state["memory"] = round(used / total * 100)


@poller(INTERVALS["reminders"])
async def poll_reminders(state: dict):
    if not shutil.which("get_reminders.sh"):
        state["reminders"] = "😠: 0"
        return await asyncio.sleep(3600)
    count = await run_cmd(["get_reminders.sh", "--count"], timeout=30)
    state["reminders"] = f"🧐: {count}" if count is not None else "😠: 0"


@poller(INTERVALS["internet"])
async def poll_internet(state: dict):
    result = await run_cmd(["ping", "-c", "1", "-W", "2", "9.9.9.9"], timeout=6)
    state["internet"] = "🥹" if result is not None else "⚠"


@poller(INTERVALS["docker"])
async def poll_docker(state: dict):
    if not shutil.which("docker"):
        state["docker"] = ""
        return await asyncio.sleep(3600)
    containers = await run_cmd(["docker", "ps"], timeout=10)
    if containers is None:
        state["docker"] = ""
        return
    running = len(containers.splitlines())
    cache = Path(os.environ.get("XDG_CACHE_DIR", "/nonexistent")) / "dotfiles" / "dockerup.update"
    updates = len(cache.read_text().splitlines()) if cache.is_file() else 0
    state["docker"] = f" 🐳: {updates}|{running}"


@poller(INTERVALS["wireguard"])
async def poll_wireguard(state: dict):
    result = await run_cmd(["wg_switcher.sh", "--query"], timeout=15)
    state["wireguard"] = "🔒✅" if result is not None else "🔒❎"


@poller(INTERVALS["battery"])
async def poll_battery(state: dict):
    batteries = sorted(Path("/sys/class/power_supply").glob("BAT*"))
    if not batteries:
        state["battery"] = ""
        return await asyncio.sleep(3600)
    capacities = []
    charging = discharging = False
    fully_charged = True
    for bat in batteries:
        status = (bat / "status").read_text().strip()
        capacities.append(int((bat / "capacity").read_text().strip()))
        if "Discharging" in status:
            discharging = True
            fully_charged = False
        elif "Charging" in status:
            charging = True
            fully_charged = False
    percentage = math.ceil(sum(capacities) / len(capacities))
    if discharging and percentage < 20:
        emoji = "❗🚨"
    elif fully_charged:
        emoji = "🔋🤪"
    elif charging:
        emoji = "🔋👍"
    else:
        emoji = "🔋👎"
    state["battery"] = f"{emoji}: {percentage}%"


async def refresh_packages(state: dict):
    output = await run_cmd(["sh", "-c", "checkupdates | wc -l"], timeout=300)
    if output is None:
        return
    PACKAGE_FILE.write_text(output + "\n")
    state["packages"] = output.strip()


@poller(INTERVALS["packages"])
async def poll_packages(state: dict):
    if not shutil.which("checkupdates"):
        state["packages"] = "?"
        return await asyncio.sleep(3600)
    # reuse a fresh cache so restarts don't re-sync pacman databases
    if PACKAGE_FILE.is_file() and time.time() - PACKAGE_FILE.stat().st_mtime < PACKAGE_CACHE_SECONDS:
        state["packages"] = PACKAGE_FILE.read_text().strip() or "?"
        return
    await refresh_packages(state)


@poller(INTERVALS["keymap"])
async def poll_keymap(state: dict):
    """Re-assert caps:escape; some keyboard hotplug events reset X options."""
    query = await run_cmd(["setxkbmap", "-query"])
    if query is not None and "caps:escape" not in query:
        await run_cmd(["setxkbmap", "-option", "caps:escape"])


def compose_status(state: dict) -> str:
    clock = datetime.now().strftime("%a-%d-%b-%H:%M")
    cpu = f'{state.get("cpu", 0):2d}'
    memory = state.get("memory", "?")
    internet = state.get("internet", "?")
    packages = state.get("packages", "?")
    reminders = state.get("reminders", "🧐: ?")
    docker = state.get("docker", "")
    tail = tag_tail(state)
    status = (
        f"{reminders} 🕒: {clock} 🧠: {memory}% 🤔:{cpu}% "
        f"🌏: {internet} 🚚: {packages}{docker}{tail}"
    )
    # late-arriving pollers leave empty gaps; collapse them
    return re.sub(r" {2,}", " ", status).strip()


def tag_tail(state: dict) -> str:
    wireguard = state.get("wireguard", "")
    battery = state.get("battery", "")
    if TAG == "hackerman":
        return f" {wireguard} {battery}".rstrip()
    if TAG == "pc":
        return f" {wireguard}".rstrip()
    return " NO TAG"


async def render_loop(state: dict, stdout_mode: bool):
    last_status = None
    while True:
        status = compose_status(state)
        if status != last_status:
            last_status = status
            if stdout_mode:
                print(status, flush=True)
            else:
                await run_cmd(["xsetroot", "-name", status], timeout=5)
        await asyncio.sleep(INTERVALS["render"])


def pollers_for_tag() -> list:
    tasks = [
        poll_cpu,
        poll_memory,
        poll_reminders,
        poll_internet,
        poll_docker,
        poll_wireguard,
        poll_packages,
    ]
    if TAG == "hackerman":
        tasks += [poll_battery, poll_keymap]
    return tasks


async def main(stdout_mode: bool):
    state: dict = {}
    polls = pollers_for_tag() + [functools.partial(render_loop, stdout_mode=stdout_mode)]
    tasks = [asyncio.create_task(poll(state)) for poll in polls]
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, tasks[0].cancel)
    try:
        await tasks[0]
    except asyncio.CancelledError:
        pass
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if not stdout_mode:
            # visible marker that the bar daemon died (mirrors old dstatus.sh trap)
            subprocess.run(["xsetroot", "-name", "😠"], check=False)


if __name__ == "__main__":
    asyncio.run(main("--stdout" in sys.argv))
