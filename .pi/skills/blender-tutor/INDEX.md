# Blender Manual Index — topic → path map

The bundled manual lives in `manual/` as greppable Markdown. This file is a hand-curated map of the sections that matter, oriented toward game development. For anything not listed here, grep the tree directly:

```bash
rg -il '<term>' .pi/skills/blender-tutor/manual/
```

Paths below are relative to `manual/`. The version bundled is in `manual/VERSION`. If it's missing or wrong, see [UPDATING.md](UPDATING.md).

## Core UI & workflow
- **User Interface** — `interface/` (window system, keymap, UI elements, tools, nodes)
- **Editors** — `editors/` (breakdown below)
- **Scenes & Objects** — `scene_layout/` (objects, collections, instancing, properties)
- **Files / IO** — `files/` (save/load, import/export, linked libraries)
- **Preferences** — `editors/preferences/`

## Editors (`editors/`)
- 3D Viewport — `editors/3dview/` (navigate, modes, toolbar, overlays, display)
- Properties — `editors/properties_editor.md`
- Outliner — `editors/outliner/`
- UV Editor — `editors/uv/`; Image Editor — `editors/image/`
- Shader Editor — `editors/shader_editor.md`; Geometry Node Editor — `editors/geometry_node.md`
- Animation editors — `editors/timeline.md`, `editors/dope_sheet/`, `editors/graph_editor/`, `editors/nla/`
- Asset Browser — `editors/asset_browser.md`; File Browser — `editors/file_browser.md`
- Developer — `editors/python_console.md`, `editors/text_editor.md`, `editors/info_editor.md`, `editors/spreadsheet.md`

## Modeling (`modeling/`)
- Meshes — `modeling/meshes/` (structure, tools, selecting, **editing** by vertex/edge/face, vertex groups)
- UV unwrapping — `modeling/meshes/uv/` (seams, unwrapping, workflows)
- Modifiers — `modeling/modifiers/` (generate: Boolean, Bevel, Mirror, Array, Subdivision Surface… / deform: Armature, Shrinkwrap, Lattice…)
- Geometry Nodes — `modeling/geometry_nodes/` (fields, attributes, instances, node reference by category)
- Curves (hair) — `modeling/curves/`, `modeling/curves_new/`
- Others — `modeling/surfaces/`, `modeling/metas/`, `modeling/texts/`, `modeling/volumes/`, `modeling/transform/`

## Sculpting & Painting (`sculpt_paint/`)
- Sculpting — `sculpt_paint/sculpting/`; Brushes — `sculpt_paint/brush/`
- Texture Paint — `sculpt_paint/texture_paint/`; Vertex Paint — `sculpt_paint/vertex_paint/`
- Weight Paint (skinning) — `sculpt_paint/weight_paint/`
- Curves Sculpting — `sculpt_paint/curves_sculpting/`

## Animation & Rigging (`animation/`)
- Armatures (skeletons/bones) — `animation/armatures/`
- Constraints — `animation/constraints/`
- Keyframes / Actions — `animation/keyframes/`, `animation/actions.md`
- Shape Keys — `animation/shape_keys/`; Drivers — `animation/drivers/`; Lattice — `animation/lattice.md`

## Rendering, Materials & Shaders (`render/`)
- Materials — `render/materials/`
- Shader Nodes (incl. Principled BSDF / PBR) — `render/shader_nodes/`
- Engines — `render/eevee/` (real-time), `render/cycles/` (path-traced), `render/workbench/`
- Lights — `render/lights/`; Cameras — `render/cameras.md`; Color Management — `render/color_management/`

## Other
- Physics — `physics/` (rigid body, cloth, fluid, collisions, particles)
- Compositing — `compositing/`; Grease Pencil (2D) — `grease_pencil/`
- Video editing — `video_editing/`; Motion tracking — `movie_clip/`
- Add-ons / Extensions — `addons/`; Advanced (Python) — `advanced/`
- Glossary — `glossary/`; Troubleshooting — `troubleshooting/`
