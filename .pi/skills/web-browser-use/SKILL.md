---
name: web-browser-use
description: "Drive a headless browser through the Playwright MCP server — navigate, read rendered pages, click, type, fill forms, scrape tables, and capture screenshots. Use when the user asks to open or browse a website, check or fill a web form, scrape JavaScript-rendered content, automate a multi-step web flow, or interact with a login-gated site. For plain keyword web search, prefer ./scripts/websearch instead of launching a full browser."
---

# Web Browser Use

## When to use a browser (vs `./scripts/websearch`)

- **`./scripts/websearch`** → plain keyword search, result links/snippets. Cheap, no browser.
- **Browser (this skill)** → anything interactive or rendered: click flows, form submission, JS-rendered pages, login-gated content, reading the live DOM, screenshots, scraping tables, multi-step automation.

If a task is just "search the web for X", try `./scripts/websearch` first. Reach for the browser when you need to *act on* or *read the rendered* page.

## The MCP gateway

All browser actions go through the `mcp` tool, server name `playwright`. Tools are named `playwright_browser_<action>`.

- Connect / list tools once at the start: `mcp({ connect: "playwright" })`
- See a tool's exact params before calling: `mcp({ describe: "playwright_browser_click" })` — **do this whenever you're unsure of a parameter name.**
- Call a tool: `mcp({ tool: "playwright_browser_navigate", args: '<JSON string>' })`

⚠️ `args` is a **JSON string**. Inner double-quotes must be escaped inside the single-quoted arg: `'{\"url\":\"https://x\"}'`.

## Quick start (the minimal loop)

```text
1. mcp connect "playwright"
2. navigate  → playwright_browser_navigate  { url }
3. read      → playwright_browser_snapshot   { }            (preferred)
              or playwright_browser_evaluate { function }
4. act       → snapshot gives element refs; pass one as `target` to click/type/etc.
```

```text
mcp({ tool: "playwright_browser_navigate", args: '{"url":"https://en.wikipedia.org"}' })
mcp({ tool: "playwright_browser_evaluate",  args: '{"function":"() => document.title"}' })
```

## Core workflow: snapshot-first (important)

`playwright_browser_snapshot` returns a YAML accessibility tree where every interactive node has a **`ref`** (e.g. `[ref=e42]`). To click/type/select that element, pass the ref as the **`target`** parameter.

```yaml
# snapshot output looks like:
- main [ref=e42]:
  - search [ref=e17]
  - link "Log in" [ref=e26] [cursor=pointer]:
    - /url: /wiki/Special:UserLogin
```

```text
mcp({ tool: "playwright_browser_click",
      args: '{"element":"Log in link","target":"e26"}' })
```

Prefer `snapshot` over `take_screenshot` for any action you intend to take — screenshots are for the human/visual check only ("You can't perform actions based on the screenshot").

## Parameter essentials (the easy mistakes)

- **`target`** *(required on most actions)* — an element `ref` from a snapshot (e.g. `"e26"`) **or** a unique CSS selector.
- **`element`** *(optional, recommended)* — a human-readable label of what you're interacting with, e.g. `"Search button"`. Aids permission logging; does **not** target the element.
- **`playwright_browser_evaluate`** takes **`function`**, an arrow-function string — NOT `expression`/`code`:
  `{"function":"() => ({title: document.title, h1: document.querySelector('h1')?.innerText})"}`
- **Don't know a param name?** `mcp({ describe: "playwright_browser_<x>" })` returns the full schema. Cheaper than a failed call.

## 🛑 Captcha & human-verification — STOP and ask

If the page shows any human-verification challenge, **do not attempt to solve or bypass it.** Halt and hand off to the user.

Detect: reCAPTCHA / hCaptcha / Turnstile / "Verify you are human" / Cloudflare "Just a moment…" interstitial / "Press & hold" / puzzle sliders / "checking your browser".

When you hit one:

1. Stop the automation. Do **not** click through, solve puzzles, or retry in a loop.
2. Tell the user: which site/page, what kind of challenge it is, and what you were trying to do.
3. Offer options: they solve it in the running browser session (you then `snapshot`/continue), they paste cookies/credentials, or you switch approach (e.g. back to `./scripts/websearch`, an API, or a different source).
4. Resume only after the user confirms humanness is proven.

This also applies to login walls you can't auth with provided credentials — ask, don't guess passwords.

## Session lifecycle

- The browser **persists across calls** within a session (cookies, tabs, state retained). Usually `connect` once.
- **When done**, close it: `mcp({ tool: "playwright_browser_close" })`. Don't leave it dangling.
- Multi-tab: `playwright_browser_tabs` with `action: "list" | "new" | "select" | "close"`.

## Recipes

**Scrape a table / structured data** (one round-trip, no clicking):
```text
mcp({ tool: "playwright_browser_evaluate", args: '{"function":"() => [...document.querySelectorAll(\"table tr\")].map(tr => [...tr.children].map(td => td.innerText))"}' })
```

**Fill & submit a form** (multiple fields, one call):
```text
mcp({ tool: "playwright_browser_fill_form", args: '{"fields":[{"element":"username","target":"#user","name":"Username","type":"textbox","value":"alice"},{"element":"remember","target":"#remember","name":"Remember me","type":"checkbox","value":"true"}]}' })
```

**Type into a field and submit** (Enter after):
```text
mcp({ tool: "playwright_browser_type", args: '{"element":"search box","target":"e17","text":"ada lovelace","submit":true}' })
```

**Screenshot to a file** (visual evidence):
```text
mcp({ tool: "playwright_browser_take_screenshot", args: '{"type":"png","filename":"after-login.png"}' })
```

**Wait for content before snapshotting:**
```text
mcp({ tool: "playwright_browser_wait_for", args: '{"text":"Results"}' })
```

**Inspect a failing page** — console + network:
```text
mcp({ tool: "playwright_browser_console_messages", args: '{"level":"error"}' })
mcp({ tool: "playwright_browser_network_requests", args: '{"filter":"/api/.*"}' })
```

## Tool map

23 tools, grouped. Full parameter reference: [REFERENCE.md](REFERENCE.md).

- **Session/nav:** `navigate`, `navigate_back`, `tabs`, `resize`, `close`
- **Observe:** `snapshot` ★, `evaluate`, `take_screenshot`, `console_messages`, `network_requests`, `network_request`
- **Act:** `click`, `hover`, `drag`, `drop`, `type`, `fill_form`, `press_key`, `select_option`, `file_upload`, `handle_dialog`, `wait_for`
- **Advanced:** `run_code_unsafe` (arbitrary Playwright snippet — last resort)

★ = your default "read the page" tool.
