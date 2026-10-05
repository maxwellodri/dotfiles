//! xidle — print ms since the last real user input, from the kernel evdev
//! layer (/dev/input). Idle is only reset by actual input devices: programs
//! resetting X counters (mpv, firefox, steam via XResetScreenSaver) cannot
//! write to evdev, so they cannot fake presence. The stateless query keeps
//! an internal daemon (same binary, `--daemon`) alive that timestamps every
//! input event to a runtime-dir state file.

use anyhow::{bail, Context, Result};
use std::fs;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const EV_KEY: u16 = 0x01;
const EV_REL: u16 = 0x07;
const HEARTBEAT_MS: u64 = 5_000;
const STALE_MS: u64 = 15_000;

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

fn state_path() -> PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() }));
    PathBuf::from(dir).join("xidle.state")
}

fn read_state() -> Option<(u64, u64)> {
    let s = fs::read_to_string(state_path()).ok()?;
    let mut it = s.split_whitespace().filter_map(|n| n.parse::<u64>().ok());
    Some((it.next()?, it.next()?))
}

fn state_is_fresh() -> Option<(u64, u64)> {
    let (last, beat) = read_state()?;
    (now_ms().saturating_sub(beat) < STALE_MS).then_some((last, beat))
}

fn write_state(last_input: u64) {
    let path = state_path();
    let tmp = path.with_extension("tmp");
    if fs::write(&tmp, format!("{last_input} {}\n", now_ms())).is_ok() {
        let _ = fs::rename(&tmp, &path);
    }
}

fn spawn_daemon_and_wait() -> Result<()> {
    let exe = std::env::current_exe().context("cannot resolve own path")?;
    let mut cmd = Command::new(exe);
    cmd.arg("--daemon")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    unsafe {
        cmd.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    cmd.spawn().context("cannot spawn daemon")?;
    for _ in 0..60 {
        if state_is_fresh().is_some() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    bail!("daemon did not come up")
}

fn query() -> Result<()> {
    if state_is_fresh().is_none() {
        spawn_daemon_and_wait()?;
    }
    match state_is_fresh() {
        Some((last_input, _)) => println!("{}", now_ms().saturating_sub(last_input)),
        None => bail!("no fresh state"),
    }
    Ok(())
}

/// A watched input device: fd plus a read buffer for partial input_event reads.
struct Device {
    file: fs::File,
    buf: Vec<u8>,
}

fn daemon() -> Result<()> {
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(state_path().with_extension("lock"))
        .context("cannot open lock")?;
    // single instance; the loser exits cleanly
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Ok(());
    }

    let mut devices = open_input_devices();
    let mut last_input = now_ms();
    write_state(last_input); // conservative: assume just-active on start
    let mut last_beat = 0u64;

    let mut polls = Vec::new();
    loop {
        let now = now_ms();
        if now - last_beat >= HEARTBEAT_MS {
            write_state(last_input);
            last_beat = now;
        }
        polls.clear();
        for d in &devices {
            polls.push(libc::pollfd {
                fd: d.file.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let rc = unsafe { libc::poll(polls.as_mut_ptr(), polls.len() as u64, 1_000) };
        if rc <= 0 {
            continue;
        }
        let mut i = 0;
        while i < devices.len() {
            if polls[i].revents & libc::POLLIN == 0 {
                if polls[i].revents & libc::POLLERR != 0 {
                    devices.swap_remove(i);
                    continue;
                }
                i += 1;
                continue;
            }
            let mut chunk = [0u8; 512];
            match devices[i].file.read(&mut chunk) {
                Ok(0) => {
                    devices.swap_remove(i);
                    continue;
                }
                Ok(n) => {
                    devices[i].buf.extend_from_slice(&chunk[..n]);
                    if consume_events(&mut devices[i]) {
                        last_input = now_ms();
                    }
                }
                Err(_) => {
                    devices.swap_remove(i);
                    continue;
                }
            }
            i += 1;
        }
    }
}

/// Drain buffered events; true if any EV_KEY/EV_REL arrived.
/// Devices are pre-filtered to keys/relative axes, so sticks, touchpads and
/// sensors (pure EV_ABS) cannot fake presence either.
fn consume_events(dev: &mut Device) -> bool {
    const EV_SIZE: usize = std::mem::size_of::<libc::input_event>();
    let mut input = false;
    for ev in dev.buf.chunks_exact(EV_SIZE) {
        let kind = u16::from_ne_bytes([ev[16], ev[17]]);
        if kind == EV_KEY || kind == EV_REL {
            input = true;
        }
    }
    let leftover = dev.buf.len() % EV_SIZE;
    dev.buf.drain(..dev.buf.len() - leftover);
    input
}

/// Open every readable /dev/input/event* that can emit keys or relative axes.
fn open_input_devices() -> Vec<Device> {
    let mut devices = Vec::new();
    let Ok(entries) = fs::read_dir("/dev/input") else {
        return devices;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if !name.starts_with("event") {
            continue;
        }
        let Ok(file) = fs::OpenOptions::new().read(true).open(entry.path()) else {
            continue;
        };
        // EVIOCGBIT(0, 4): capability bitmap for event types
        let ioctl = (2u64 << 30) | (4 << 16) | (0x45 << 8) | 0x20;
        let mut caps = [0u8; 4];
        let rc =
            unsafe { libc::ioctl(file.as_raw_fd(), ioctl as libc::c_ulong, caps.as_mut_ptr()) };
        if rc < 0 {
            continue;
        }
        let has_key = caps[0] & (1 << EV_KEY) != 0;
        let has_rel = caps[0] & (1 << EV_REL) != 0;
        if has_key || has_rel {
            devices.push(Device {
                file,
                buf: Vec::new(),
            });
        }
    }
    devices
}

fn main() -> Result<()> {
    if std::env::args().nth(1).as_deref() == Some("--daemon") {
        daemon()
    } else {
        query()
    }
}
