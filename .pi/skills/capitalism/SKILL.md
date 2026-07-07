---
name: capitalism
description: Search for products, compare prices across stores, check availability, and find compatible hardware. Use when the user asks to go shopping or find items to buy.
---

# Capitalism

## Defaults

- **Currency:** AUD
- **Region:** Australia, Brisbane (for shipping purposes)
- **Stores:** Australian storefronts first; international only if item is unavailable in AU or inherently international (e.g. Valve hardware)
- **Read-only:** NEVER purchase, add to cart, or submit any order. The agent finds the best deals and presents links — user buys manually.

## Terminology

- **product query** — what the user wants to find (can be vague: "RAM to upgrade to 64GB")
- **intervention** — agent pauses browsing and pings user to handle CAPTCHA, login, or age verification in the visible browser window (Playwright only)
- **comparison table** — markdown table with product, price (AUD), rating, availability, store, link

## Tools

| Tool | Purpose | Required |
|------|---------|----------|
| `websearch` | Brave Search API wrapper. Primary product discovery and price comparison. AU/EN defaults, clean text output or raw JSON with `-j`. On `$PATH` — invoke as bare `websearch`. | Yes |
| staticICE (`staticice.com.au`) | AU price aggregator. First port of call for comparing prices across all AU stores at once. Playwright is needed to scrape it. | No (but strongly recommended) |
| Playwright MCP | Browser automation for scraping staticICE and deep-diving individual store pages (detailed specs, shipping thresholds, stock verification). **Browsing is read-only (no disk modifications) — it IS planning.** | No |

## Harness differences

This skill runs under multiple harnesses. Some expose a single **MCP gateway**
tool and spawn MCP servers (like Playwright) lazily on demand; others expose MCP
tools by their direct names and require the user to enable the server manually
first. The pre-flight script (`scripts/capitalism_check.sh`) detects which style
is in use (via `$PI_CODING_AGENT_DIR`) and prints the correct guidance. Key
differences:

| Concern | Harness with MCP gateway | Harness with direct MCP tools |
|---|---|---|
| Playwright MCP enable | Automatic — lazy on demand via the gateway tool (the server spawns only when a browser tool is actually called) | Manual: enable the playwright MCP in the TUI first, then continue |
| Calling browser tools | Via the gateway: `mcp({ tool: "playwright_browser_navigate", args: { url } })`. Discover with `mcp({ search: "browser" })` | Direct tool names, e.g. `playwright_browser_navigate({ url })` |
| Plan/build-mode gate | N/A — no plan mode; proceed directly | Applies — see step 0 (requires plan mode) |
| Detection | `$PI_CODING_AGENT_DIR` is set | absence of `$PI_CODING_AGENT_DIR` |

When a gateway tool is available, route every browser action through it rather
than calling `playwright_*` tools by name.

## Quick Start

1. User describes what they need: "find me wireless headphones under $100"
2. Run pre-flight check — verify `websearch` is functional
3. Search using `websearch` for broad discovery, then store-specific queries
4. If more detail is needed (specs, shipping, stock), optionally use Playwright to scrape individual store pages
5. Extract prices, ratings, availability into a comparison table (all AUD)
6. Present table sorted by best value

## Workflow

### 0. Build mode gate (harnesses with a build/plan split only)

> Skip this step on harnesses without a plan mode — go straight to step 1.

If your harness distinguishes **build mode** (no side effects) from **plan mode** (research + planning) and you are in build mode, REFUSE to continue. Tell the user:

> Capitalism skill requires plan mode. Browsing stores and comparing prices is research (read-only, no disk modifications). Re-invoke with plan mode enabled so I can structure research, compare deals, and present findings properly.

Do not proceed with any browsing, websearch queries, or Playwright navigation outside plan mode. Playwright browsing IS planning — it only reads web pages and never modifies files on disk.

### 1. Pre-flight

```bash
bash scripts/capitalism_check.sh
```

This checks that `websearch` dependencies are met (curl, jq, pass with `brave_search_api_key`). Playwright checks are optional — the skill is fully functional without it.

If Playwright MCP tools are not available, note it to the user but continue — `websearch` handles most product research without a browser.

### 2. Gather context (if needed)

If the user specifies a hardware requirement (e.g. "DDR5 RAM", "PCIe 4.0 NVMe"), trust their spec. Only check the local machine if they explicitly ask to verify compatibility. Do not assume they want parts for this machine.

### 3. Price comparison with staticICE (first port of call)

Use Playwright to search [staticICE](https://www.staticice.com.au) — an AU price aggregator that lists products from dozens of stores sorted by price. It gives instant across-store comparisons and is the fastest way to find the best price.

```text
https://www.staticice.com.au/cgi-bin/search.cgi?q={query}
```

**Extraction:** staticICE renders server-side — no JS wait needed. Use `browser_evaluate` to read `document.body.innerText` and parse the text (prices, store names, product descriptions). The page layout is simple: a table with Price and Description columns.

```javascript
// Extract first ~3000 chars of page text — contains all results
document.body.innerText.substring(0, 3000)
```

Run separate staticICE queries for each product variant or model number. staticICE is especially good for:
- Finding the cheapest price across ALL AU stores (including smaller ones like MSY, CCPU, CPL)
- Verifying stock status and last-updated timestamps
- Comparing exact model numbers

### 4. Search with websearch (supplementary discovery)

After staticICE, use `websearch` for supplementary discovery — finding products that staticICE might not index (new releases, Amazon-only listings, niche items):

**Broad discovery:**
```bash
websearch "wireless headphones under 100 AUD buy Australia"
```

**Store-scoped searches** (target specific stores from REFERENCE.md):
```bash
websearch "wireless headphones site:amazon.com.au OR site:jbhifi.com.au OR site:scorptec.com.au"
```

**Structured extraction** (when you want to parse results programmatically):
```bash
websearch -j "DDR5-5600 32GB RAM kit Australia"
```

Each result includes: title, URL, description (HTML tags stripped). Build the comparison table directly from these fields.

Repeat with varied queries to cover different stores and product variants.

**Free shipping:** If an item's price meets a store's free shipping threshold (see REFERENCE.md), treat shipping as free. Do not assume any paid membership (e.g. Amazon Prime).

### 5. Deep-dive with Playwright (optional)

If `websearch` results lack sufficient detail (missing prices, specs, stock status, shipping info), use Playwright MCP to scrape individual store pages:

1. `browser_navigate` to the product page URL from `websearch` results
2. `browser_wait_for` — wait for content to load (especially Scorptec, PCCG — JS-heavy)
3. `browser_snapshot` or `browser_evaluate` to extract structured product data
4. Follow the [fallback hierarchy](REFERENCE.md) if extraction fails (selectors → innerText → snapshot → webfetch)

This step is optional. Skip it if `websearch` results already provide enough detail for the comparison table.

### 6. Preserve un-extractable pages (Playwright only)

If you navigated to a product page via Playwright but **cannot extract useful data** after trying the full extraction hierarchy (selectors → innerText → snapshot), do **not** navigate away or close the tab. Instead:

1. Use `browser_tabs` to **open a new tab** for the next page you need to visit
2. Leave the un-extractable product page tab open in the browser
3. In the comparison table, include the product with whatever partial info you have (even just the URL) and mark it `⚠ manual review`
4. At the end, tell the user how many tabs are left open for manual review

The browser is a visible ungoogled-chromium window — the user can review these tabs themselves after the agent finishes. This avoids losing useful product pages just because automated extraction failed.

**When to preserve:** Any product page where the extraction hierarchy (see REFERENCE.md) exhausted all options and returned empty or unusable data. Common causes: heavy JS rendering, anti-bot obfuscation, unconventional page layouts, image-based pricing.

### 7. Interventions (Playwright only)

When using Playwright and you hit a CAPTCHA, login wall, or age verification:
1. Stop browsing
2. Tell the user: "I need you to handle a [CAPTCHA/login] in the browser window"
3. Wait for user confirmation
4. Continue with `browser_snapshot`

### 8. Present results

Output a markdown comparison table (all prices AUD):

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |

Rows for preserved (un-extractable) pages should include `⚠ manual review` in the Price column and whatever partial info is available. Sort by best value (price + rating + availability + shipping), with manual-review rows at the bottom.

If any tabs were preserved, add a note: "N product page(s) left open in browser for manual review."

### 9. Agent feedback

After presenting results, briefly note:
- Any difficulties encountered (missing prices, blocked queries, sparse results)
- Whether Playwright was needed or `websearch` alone sufficed
- Suggestions for improving this skill, scripts, or workflow
- Stores that would be useful to add

### 10. Follow-up

User may ask to narrow results, check more stores, open product pages, or compare products.

## Review Checklist

- [ ] Build mode gate enforced — refused if in build mode
- [ ] Pre-flight check passed (websearch functional)
- [ ] staticICE checked as first port of call (if Playwright available)
- [ ] `websearch` used for supplementary product discovery
- [ ] At least 2 stores represented in results (AU storefronts first)
- [ ] All prices in AUD
- [ ] Free shipping noted where threshold is met (no membership assumptions)
- [ ] Playwright used only when websearch results were insufficient (or not at all)
- [ ] User pinged for any CAPTCHA/login walls (Playwright only)
- [ ] Un-extractable product pages preserved as open tabs (Playwright only, not closed/navigated away)
- [ ] Preserved tabs noted in comparison table with `⚠ manual review`
- [ ] Compatibility checked only if user explicitly asked
- [ ] No purchase actions taken — only research and price comparison
- [ ] Agent feedback on workflow improvements included
