# Live Blender mode — mechanics & snippets

Sub-skill of [SKILL.md](SKILL.md). Read this once before using live mode, then
refer back for the snippets. **Teach, don't do** still applies — live mode is for
*inspection and demonstration*, not for finishing the user's work.

The server is `ahujasid/blender-mcp` (third-party, not official Blender). Two
parts: a Blender addon that opens a socket on `localhost:9876` and runs commands
on Blender's main thread (via `bpy.app.timers`, so it's thread-safe), and an MCP
server (`uvx blender-mcp`) bridging stdio↔socket.

## 0. The connection is lazy — probe once, then degrade gracefully

`blender` is `lifecycle: "lazy"`. It does **not** start at pi launch; `uvx` only
spawns the first time you call one of its tools, and it disconnects after 10 min
idle. So:

1. Probe once:  `mcp({ connect: "blender" })`
2. If it errors → **don't retry.** Fall back to manual coaching (SKILL.md) and
   tell the user how to enable live mode (section below). One failed probe is
   enough to know Blender/addon isn't ready.

If you want to see the user's scene or read their keymap, lead with the probe,
then proceed. Cached metadata means `mcp({ server: "blender" })` / `search` work
even without a live connection, but tool *calls* need it.

## 1. Enabling live mode (one-time, tell the user)

1. Download `addon.py` from `github.com/ahujasid/blender-mcp`.
2. Blender ▸ Edit ▸ Preferences ▸ Add-ons ▸ Install… ▸ pick `addon.py`.
3. Enable the checkbox beside **Interface: Blender MCP**.
4. 3D Viewport ▸ press `N` ▸ **BlenderMCP** tab ▸ **Connect to Claude**.
5. Blender must run with a GUI — the addon refuses to start under `blender -b`
   (commands would never execute). On a headless box use `xvfb-run -a blender`.

## 2. Tool calls (via the proxy `mcp` tool, prefixed `blender_`)

The server is behind the proxy (no `directTools`), so everything goes through the
`mcp` tool. Names are prefixed `blender_<tool>`. Relevant ones for tutoring:

| Prefixed name | What it does |
|---|---|
| `blender_get_scene_info` | Object list (capped ~10), counts. Needs `user_prompt`. |
| `blender_get_object_info` | Full transform, mesh vert/edge/face counts, materials, world AABB. `object_name`. |
| `blender_get_viewport_screenshot` | Renders the viewport **offscreen** (works even if Blender isn't foregrounded) → Image you can view. Optional `max_size`. |
| `blender_execute_blender_code` | Run arbitrary `bpy` Python on Blender's main thread; **returns captured stdout** (so `print()` your results). `code`. |

> `user_prompt` is a telemetry artifact (we run `DISABLE_TELEMETRY=true`) — pass
> any short string; it's ignored. For `execute_blender_code`, data only comes
> back via `print()`, and the namespace is fresh each call (no state between
> calls except changes to `bpy.data`).

Patterns:
```
mcp({ tool: "blender_get_viewport_screenshot", args: '{"max_size": 1000}' })        # → image
mcp({ tool: "blender_get_object_info",         args: '{"object_name":"Cube"}' })
mcp({ tool: "blender_execute_blender_code",     args: '{"code":"import bpy; print(len(bpy.data.objects))"}' })
```

## 3. Seeing the scene (prefer the dedicated tools over hand-written code)

For critique, the screenshot is the highest-value tool — actually look at it:

```
mcp({ tool: "blender_get_viewport_screenshot", args: '{"max_size": 1000}' })
```

Then `get_scene_info` / `get_object_info` for specifics (poly count to flag
triangle-budget issues, world AABB to spot clipping, materials to check a PBR
setup). Teach from what you see, cite the manual path for the *why*.

## 4. Reading the user's *real* keymap

This beats the manual's defaults because it reflects their actual bindings
(incl. custom keymaps). Via `execute_blender_code`:

**List everything** (good first look):
```python
import bpy
def mods(k):
    m=[]
    if k.ctrl: m.append("Ctrl")
    if k.shift: m.append("Shift")
    if k.alt: m.append("Alt")
    if k.oskey: m.append("Os")
    return "+".join(m+[k.type])
kc=bpy.context.window_manager.keyconfigs.user          # 'Blender user' = their bindings
out=[]
for km in kc.keymaps:
    for kmi in km.keymap_items:
        out.append(f"{mods(kmi):<16} {kmi.name:<36} {kmi.idname}   [{km.name}]")
print("\n".join(sorted(out)))
```

**"What does key X do?"** (e.g. `E`):
```python
import bpy
key="E"
for km in bpy.context.window_manager.keyconfigs.user.keymaps:
    for kmi in km.keymap_items:
        if kmi.type==key and kmi.value in ('PRESS','CLICK'):
            print(f"{key}: {kmi.name} [{kmi.idname}]  in '{km.name}'  "
                  f"ctrl={kmi.ctrl} shift={kmi.shift} alt={kmi.alt}")
```

**"What's the hotkey for <Y>?"** (e.g. extrude):
```python
import bpy
n="extrude"
for km in bpy.context.window_manager.keyconfigs.user.keymaps:
    for kmi in km.keymap_items:
        if n in kmi.name.lower() or n in kmi.idname.lower():
            print(f"{kmi.name}: {kmi.type} [{kmi.idname}]  in '{km.name}'")
```

> Use `keyconfigs.user` (their customizations). `keyconfigs.active` is a merge
> and `keyconfigs['Blender']` is the factory default — fine for cross-checking,
> but the user's *real* answer is `.user`.

## 5. "Pinging a button" = calling its operator

**Every UI button in Blender is an operator** (`bpy.ops.*`). The MCP lets you run
any of them as a *demonstration*. The catch: many operators need a 3D-viewport
context, and code running from the MCP timer has only a generic `bpy.context`.
Supply it with `temp_override`:

```python
import bpy
area=next(a for a in bpy.context.screen.areas if a.type=='VIEW_3D')
region=next(r for r in area.regions if r.type=='WINDOW')
with bpy.context.temp_override(area=area, region=region):
    bpy.ops.object.shade_smooth()    # <-- the operator behind the "Shade Smooth" button
print("ran:", "object.shade_smooth")
```

**Reliability:**
- **Object-mode operators** (shade smooth/flat, origin, apply transforms, join,
  parent, add via `object.*`, etc.) — reliable; they mostly need an active
  object + the area override.
- **Edit-mode mesh operators** (extrude, inset, bevel, loop cut…) — **flaky**.
  They need the object in Edit mode *and* the mesh as the edit-object in context.
  If one fails with `Operator poll() failed`, don't fight it — that's your cue to
  **guide the user to do it themselves** with the hotkey/menu (which is the more
  pedagogical move anyway).

**How to find the operator behind a button** if you don't know its idname:
- Hover the button in Blender → it shows the operator in the tooltip / Info editor.
- Or grep the keymap by name (section 4) — `kmi.idname` is the operator string.
- Common ones are obvious: `object.shade_smooth`, `object.transform_apply`,
  `object.join`, `object.parent_set`, `mesh.extrude_region`, `mesh.inset_faces`,
  `mesh.bevel`, `mesh.loop_cut`, `object.mode_set` (switch modes), etc.

**Demonstrate, then hand off.** After firing an operator, tell the user *how to
do it themselves* (the menu path + the hotkey from their keymap), and prefer
having them do the next one. Never turn a demo into "I built your scene for you."
