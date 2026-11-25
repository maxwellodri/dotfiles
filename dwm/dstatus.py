#!/usr/bin/env python3
"""dwm status bar: async pollers feed shared state; renderer calls xsetroot on change.

Each data source polls on its own cadence so nothing blocks the 1s render loop.
Heavy commands (docker, wg, ping, checkupdates) run minutes apart, not per tick.
"""

from __future__ import annotations

import asyncio
import contextlib
import functools
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
PACKAGE_FILE = SCRIPT_DIR / "package_file.txt"
PACKAGE_CACHE_SECONDS = 3600

INTERVALS = {
    "cpu": 2,
    "memory": 2,
    "reminders": 60,
    "internet": 30,
    "docker": 60,
    "wireguard": 5,
    "battery": 30,
    "bluetooth": 15,
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
            start_new_session=True,
        )
    except (FileNotFoundError, PermissionError, OSError):
        return None
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        # kill the whole group: grandchildren (e.g. checkupdates under
        # `sh -c`) inherit the stdout pipe, and an abandoned communicate()
        # blocked on that pipe never completes — the task becomes
        # uncancellable and wedges the shutdown gather forever
        with contextlib.suppress(OSError):
            os.killpg(proc.pid, signal.SIGKILL)
        with contextlib.suppress(Exception):
            await asyncio.wait_for(proc.wait(), 5)
        return None
    if proc.returncode != 0:
        return None
    return stdout.decode(errors="replace").strip()


async def run_once(poll, state: dict):
    try:
        return await poll(state)
    except asyncio.CancelledError:
        raise
    except Exception:
        traceback.print_exc()


def poller(interval: int):
    """Decorate an async poller: run once immediately, then every interval.

    A failed run keeps the previous state instead of blanking the bar.
    A poller may return a delay to override the default interval.
    """

    def wrap(func):
        async def run(state: dict):
            while True:
                delay = await run_once(func, state)
                await asyncio.sleep(delay or interval)

        run.once = func
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
        return 3600
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
        return 3600
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
        return 3600
    capacities = []
    charging = discharging = False
    fully_charged = True
    for bat in batteries:
        status = (bat / "status").read_text().strip()
        capacity = int((bat / "capacity").read_text().strip())
        try:
            end_threshold = int((bat / "charge_control_end_threshold").read_text())
        except (OSError, ValueError):
            end_threshold = 100
        # scale by stop threshold: 78% held at an 80% ceiling is effectively full
        if 0 < end_threshold < 100:
            capacity = min(100, capacity * 100 / end_threshold)
        capacities.append(capacity)
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


def parse_battery_level(info: str) -> int | None:
    for line in info.splitlines():
        if "Battery Percentage" not in line:
            continue
        numbers = re.findall(r"\d+", line)
        if numbers and int(numbers[-1]) <= 100:
            return int(numbers[-1])
    return None


@poller(INTERVALS["bluetooth"])
async def poll_bluetooth(state: dict):
    if not shutil.which("bluetoothctl"):
        state["bluetooth"] = ""
        return 3600
    connected = await run_cmd(["bluetoothctl", "devices", "Connected"], timeout=10)
    if connected is None:
        state["bluetooth"] = ""
        return
    levels = []
    for line in connected.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2 or parts[0] != "Device":
            continue
        info = await run_cmd(["bluetoothctl", "info", parts[1]], timeout=10)
        level = parse_battery_level(info) if info else None
        level = "--" if level is None else level
        levels.append(f"🔷: {level:>3}%")
    state["bluetooth"] = " ".join(levels)


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
        return 3600
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
    status = re.sub(r" {2,}", " ", status).strip()
    bluetooth = state.get("bluetooth", "")
    return f"{bluetooth} {status}" if bluetooth else status


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
        try:
            status = compose_status(state)
            if status != last_status:
                last_status = status
                if stdout_mode:
                    print(status, flush=True)
                else:
                    await run_cmd(["xsetroot", "-name", status], timeout=5)
        except asyncio.CancelledError:
            raise
        except Exception:
            traceback.print_exc()
        await asyncio.sleep(INTERVALS["render"])


def pollers_for_tag() -> list:
    tasks = [
        poll_cpu,
        poll_memory,
        poll_reminders,
        poll_internet,
        poll_docker,
        poll_wireguard,
        poll_bluetooth,
        poll_packages,
    ]
    if TAG == "hackerman":
        tasks += [poll_battery]
    return tasks


async def snapshot() -> str:
    state: dict = {}
    await asyncio.gather(*(run_once(poll.once, state) for poll in pollers_for_tag()))
    await asyncio.sleep(1)
    await run_once(poll_cpu.once, state)
    return compose_status(state)


async def main(stdout_mode: bool):
    state: dict = {}
    polls = pollers_for_tag()
    if TAG == "hackerman":
        polls.append(poll_keymap)
    polls.append(functools.partial(render_loop, stdout_mode=stdout_mode))
    tasks = [asyncio.create_task(poll(state)) for poll in polls]
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    await stop.wait()
    for task in tasks:
        task.cancel()
    # bounded shutdown: a task stuck in uncancellable cleanup must not leave
    # a zombie process freezing the bar at its last render
    await asyncio.wait(tasks, timeout=10)
    if not stdout_mode:
        # visible marker that the bar daemon died (mirrors old dstatus.sh trap)
        subprocess.run(["xsetroot", "-name", "😠"], check=False)


if __name__ == "__main__":
    if "--test" in sys.argv:
        print(asyncio.run(snapshot()))
    else:
        asyncio.run(main("--stdout" in sys.argv))
