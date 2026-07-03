---
name: gui-demo
description: "Create interactive single-file HTML demos with inlined CSS/JS, dark theme, and Canvas-based visualizations. Use when the user asks to make a GUI demo, interactive HTML, visualize something, math graph, HTML widget, playground, or quick visual demo."
---

# GUI Demo

Create single-file interactive HTML demos. Everything inlined (CSS/JS), dark themed, open directly in a browser. Quick to make, test, throw away.

## Quick Start

When the user asks for a demo, produce a single `.html` file with this structure:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><!-- descriptive title --></title>
<style>
/* paste contents of reference.css here */
</style>
</head>
<body>
<h1><!-- title --></h1>
<div class="controls">
  <!-- sliders, buttons, inputs -->
</div>
<canvas id="canvas" width="800" height="600"></canvas>
<script>
// all JS inline
</script>
</body>
</html>
```

## Workflow

1. **Understand the request** — what should the demo visualize or interact with?
2. **Pick a filename** — user-specified path, or `<relevant_name>.html` in PWD
3. **Inline dark CSS** — copy the full contents of [reference.css](reference.css) into `<style>` tags
4. **Choose rendering approach:**
   - **Canvas API** (default) — math plots, curves, fractals, particle systems, anything custom. Zero dependencies.
   - **Mermaid.js** (diagrams only) — flowcharts, sequence diagrams, class diagrams, state diagrams, ER diagrams. Load from CDN:
     ```html
     <script type="module">
       import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.esm.min.mjs';
       mermaid.initialize({ startOnLoad: true, theme: 'dark' });
     </script>
     ```
     Define diagrams in `<pre class="mermaid">` blocks. Requires internet on first load.
5. **Build interactive controls** — sliders, buttons, number inputs. Wire them to redraw/update functions.
6. **Write the file** — single `.html`, everything inlined
7. **Test** — suggest `firefox <file>.html` to open

## Guidelines

- **Single file** — all CSS in `<style>`, all JS in `<script>`, no external files (except Mermaid CDN)
- **Dark theme** — always use the bundled dark CSS from reference.css
- **Interactive** — demos should have controls (sliders, buttons, inputs) that change the visualization in real-time
- **Self-contained** — works by opening the file directly in a browser
- **Quick and dirty** — minimal code, get it working fast
- **Shareable** — one file, easy to upload or send
- **No build steps** — no npm, no bundlers, no frameworks

## Canvas Tips

- Use `requestAnimationFrame` for smooth animation loops
- Map math coordinates to canvas pixels:
  ```js
  const cx = (x - xMin) / (xMax - xMin) * canvas.width;
  const cy = canvas.height - (y - yMin) / (yMax - yMin) * canvas.height;
  ```
- Clear before redraw: `ctx.clearRect(0, 0, canvas.width, canvas.height)`
- Draw axes/grid first, then data
- For responsive canvas, set `width`/`height` via JS on window resize

## Mermaid Tips

- Use ONLY for diagrams — never for math plots, curves, or data visualization (use Canvas for those)
- Wrap diagram code in `<pre class="mermaid">` blocks
- Set `theme: 'dark'` to match the dark CSS
- Requires internet to load from CDN (caches after first load)
- Mermaid is ~3.3MB — fine from CDN but noted for offline use

## Examples

Working demos in [examples/](examples/) you can reference for patterns:

- **[stickiness.html](examples/stickiness.html)** — Slider-driven 2D curve plot. Range sliders control math parameters, primary curve (bright) shows current values, ghost curves (faint) show alternates. Includes grid, axis labels, and formula display. A good template for any "plot Y vs X with tunable parameters" request.
