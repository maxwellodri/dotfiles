---
name: gui-automation
license: MIT
description: Use when presenting a GUI to the user OR when testing GUI code yourself.
---
This skill only applies to non-web UIs. For web UIs, use the `web-browser-use` skill instead.
Gate all host-display behaviour on `$dotfile_tag`.
- `hackerman`/`pc` are the user's personal devices: pin every window the agent spawns with `DWM_FORCE_MONITOR=0 DWM_FORCE_TAG=8` (dwm reads these from the client's environment; export on the launcher so whole process trees inherit them), and never screenshot the host display: the user works concurrently, tag 8 isn't focused, and a host screenshot would capture their unrelated work. If you need a screenshot or other interaction to test, see below.
- `snuggy` is a standalone server: nobody is watching, go wild.

# Handoff GUIs to the user
Whenever you present a GUI for the user to test/interact with; where a GUI is defined as spawning *any* X11/Wayland window; including for them to approve e.g.a  oneoff demo or if you feel a feature is "done", then:
Set env vars DWM_FORCE_TAG=8 and DWM_FORCE_MONITOR=0 to the process that spawns the window, e.g. `DWM_FORCE_TAG=8 DWM_FORCE_MONITOR=0 cargo lrun`

# LLM driven manual testing of GUIs
If "done" requires you to verify GUI code then use the `~/source/gui_automation` repo (lowercase; commands replicate its README.md — keep in sync:
`export GA_INSTANCE=$(uuidgen)` is REQUIRED for every ga command, then `./ga image build` once,
`./ga up`, `./ga session start`, `./ga app start [--bin PATH]`, `./ga snap` → screenshot to `/tmp/ga_<id>_snap.png`,
and `ga key/type/move/clickat/click/drag/boxselect/wheel/focus/geometry/ssh/status --all/down` for driving it;
coordinates are guest pixels, snap → read via the `image` subagent → act → snap).
Once you're done, when handing back to the user, ensure you spin down the VM. The VM is not visible to the user; so if the user also asks for a demo once you've tested the GUI, you'll need to use the above env vars to spawn the program outside of the VM, in the correct tag/monitor. The VM should contain an X11 session, so use standard xdotool automation and screenshots (interpret via `image` subagent) to verify correctness. If you control the rendering of the App, it may be helpful to use bright obvious colours as debugging aids, e.g. `image` subagents will have an easier time to pick out an obvious red icon.
