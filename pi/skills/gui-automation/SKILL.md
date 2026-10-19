---
name: gui-automation
license: MIT
description: Use when presenting a gui to the user OR when testing gui code yourself.
---
If the user asks you to present a gui to them, and the code itself is obvious/testable ; simply set env vars DWM_FORCE_TAG=8 and DWM_FORCE_MONITOR=0 when running the window.
If the user asks you to test gui code, e.g. xdotool automation or screenshots; use the ~/source/gui_automation repo to spin up a VM to test the code, refer to its README.md for specific uses. Once you're done, when handing back to the user, ensure you spin down the VM. The VM is not visible to the user; so if the user also asks for a demo once you've tested the gui, you'll need to use the above env vars to spawn the program outside of the VM, in the correct tag/monitor.
To interpet screenshots of guis use the Image subagent; give the subagent specific things to confirm exist, as well as a general description.

