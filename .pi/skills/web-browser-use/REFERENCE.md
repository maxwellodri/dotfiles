# Playwright MCP — Tool Reference

All calls via `mcp({ tool: "playwright_browser_<name>", args: '<json>' })`. `args` is a JSON string.

## Conventions

- **`target`** — an element `ref` from a snapshot (e.g. `"e42"`) **or** a unique CSS selector.
- **`element`** — optional human-readable label, used for permission logging (does not target the element).
- Required params marked **(req)**. Schemas below verified against the live server; run `mcp({ describe: "playwright_browser_<name>" })` to re-confirm or for any tool not detailed here.

## Session & navigation

### playwright_browser_navigate
Navigate to a URL. After load, returns page URL/title and a snapshot reference.
- `url` **(req)** — target URL.

### playwright_browser_tabs
List, create, close, or select a tab.
- `action` **(req)** — `"list"` | `"new"` | `"close"` | `"select"`.
- `index` — tab index, for `close`/`select`. If omitted on `close`, closes the current tab.
- `url` — URL for `new`.

### playwright_browser_navigate_back / playwright_browser_resize / playwright_browser_close
`navigate_back` and `close` take no parameters. For `resize` dimensions, run `describe`.

## Observe

### playwright_browser_snapshot ★
Accessibility snapshot of the current page — **the source of element `ref`s**. Prefer this over screenshots for any action.
- `target` — snapshot a specific element (ref/selector) instead of the whole page.
- `depth` — limit the depth of the snapshot tree (use on big pages).
- `boxes` — include each element's bounding box as `[box=x,y,w,h]` (viewport-relative CSS px).
- `filename` — save to a markdown file instead of returning inline.

### playwright_browser_evaluate
Run JS on the page and return the result.
- `function` **(req)** — arrow-function string: `"() => ..."` or `"(element) => ..."` when `element` is given. **Not** `expression`/`code`.
- `element` — human-readable label.
- `target` — ref/selector the function receives as its arg.
- `filename` — save result to file.

### playwright_browser_take_screenshot
Screenshot for visual evidence only — **cannot act from a screenshot**.
- `type` **(req)** — `"png"` | `"jpeg"` (default `png`).
- `scale` **(req)** — `"css"` | `"device"` (default `css`).
- `filename` — output filename; prefer relative. Default `page-<timestamp>.<ext>`.
- `fullPage` — capture the full scrollable page (incompatible with `element`/`target`).
- `element`, `target` — capture a specific element.

### playwright_browser_console_messages
- `level` **(req)** — `"error"` | `"warning"` | `"info"` | `"debug"` (default `info`; includes more-severe).
- `all` — return messages since session start, not just last navigation.
- `filename` — save to file.

### playwright_browser_network_requests / playwright_browser_network_request
- `network_requests`: `static` **(req)** bool (include images/fonts/scripts; default `false`); `filter` regexp on URL; `filename`.
- `network_request`: takes a request number (run `describe` for exact param) — full headers/body of one request.

## Act

### playwright_browser_click
- `target` **(req)** — ref or selector.
- `element` — label.
- `doubleClick`, `button` (`"left"`|`"right"`|`"middle"`), `modifiers` (array of `"Alt"`/`"Control"`/`"ControlOrMeta"`/`"Meta"`/`"Shift"`).

### playwright_browser_hover
Hover over an element. Params: `element`, `target`. (Run `describe` to confirm.)

### playwright_browser_type
Type text into an editable element.
- `target` **(req)**, `text` **(req)**, `element`.
- `submit` — press Enter after.
- `slowly` — one char at a time (to trigger key handlers); default fills at once.

### playwright_browser_fill_form
Fill multiple fields in one call.
- `fields` **(req)** — array, each: `element`, `target` **(req)**, `name` **(req)**, `type` **(req)** (`"textbox"`|`"checkbox"`|`"radio"`|`"combobox"`|`"slider"`), `value` **(req)** (checkbox → `"true"`/`"false"`; combobox → option text).

### playwright_browser_press_key
- `key` **(req)** — key name (`"Enter"`, `"ArrowLeft"`) or a character (`"a"`).

### playwright_browser_select_option
Select dropdown option(s).
- `target` **(req)**, `values` **(req)** — array of strings; `element`.

### playwright_browser_file_upload
- `paths` — array of **absolute** file paths (omit to cancel the file chooser).

### playwright_browser_handle_dialog
Accept/dismiss a JS dialog (alert/confirm/prompt).
- `accept` **(req)** — bool.
- `promptText` — text for a prompt dialog.

### playwright_browser_wait_for
- `text` — wait for this text to appear.
- `textGone` — wait for this text to disappear.
- `time` — wait N seconds.

### playwright_browser_drag / playwright_browser_drop
Drag between elements / drop files or MIME data. Run `describe` for exact params.

## Advanced

### playwright_browser_run_code_unsafe
Run an arbitrary Playwright code snippet. **Unsafe — executes any code.** Use only as a last resort when no dedicated tool fits; prefer the typed tools above.
