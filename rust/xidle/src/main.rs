//! xidle — print milliseconds since the last real X input, via the XSync
//! IDLETIME counter. Unlike xprintidle (MIT-SCREEN-SAVER idle), IDLETIME is
//! driven only by actual input events, so screensaver inhibition (mpv,
//! firefox, steam, ... calling XResetScreenSaver / XScreenSaverSuspend) does
//! not reset it. Used by scripts/when_afk's afk_idle().

use anyhow::{bail, Context, Result};
use x11rb::protocol::sync::{list_system_counters, query_counter};

fn main() -> Result<()> {
    let (conn, _) = x11rb::connect(None).context("cannot open X display")?;
    let counters = list_system_counters(&conn)
        .map_err(|e| anyhow::anyhow!("XSync ListSystemCounters: {e}"))?
        .reply()
        .map_err(|e| anyhow::anyhow!("XSync ListSystemCounters reply: {e}"))?;
    let Some(idle_counter) = counters
        .counters
        .iter()
        .find(|c| c.name.as_slice() == b"IDLETIME")
    else {
        bail!("X server exposes no IDLETIME counter");
    };
    let value = query_counter(&conn, idle_counter.counter)
        .map_err(|e| anyhow::anyhow!("XSync QueryCounter: {e}"))?
        .reply()
        .map_err(|e| anyhow::anyhow!("XSync QueryCounter reply: {e}"))?
        .counter_value;
    let ms = ((value.hi as i64) << 32) | value.lo as i64;
    println!("{ms}");
    Ok(())
}
