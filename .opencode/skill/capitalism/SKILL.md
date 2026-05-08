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
| `scripts/websearch` | Brave Search API wrapper. Primary product discovery and price comparison. AU/EN defaults, clean text output or raw JSON with `-j`. | Yes |
| Playwright MCP | Browser automation for deep-diving individual store pages (detailed specs, shipping thresholds, stock verification). | No |

## Quick Start

1. User describes what they need: "find me wireless headphones under $100"
2. Run pre-flight check — verify `websearch` is functional
3. Search using `websearch` for broad discovery, then store-specific queries
4. If more detail is needed (specs, shipping, stock), optionally use Playwright to scrape individual store pages
5. Extract prices, ratings, availability into a comparison table (all AUD)
6. Present table sorted by best value

## Workflow

### 0. Plan mode gate

If you are NOT in plan mode, REFUSE to continue. Tell the user:

> Capitalism skill requires plan mode. Re-invoke with plan mode enabled so I can structure research, compare deals, and present findings properly.

Do not proceed with any browsing or research outside plan mode.

### 1. Pre-flight

```bash
bash .opencode/skill/capitalism/scripts/capitalism_check.sh
```

This checks that `websearch` dependencies are met (curl, jq, pass with `brave_search_api_key`). Playwright checks are optional — the skill is fully functional without it.

If Playwright MCP tools are not available, note it to the user but continue — `websearch` handles most product research without a browser.

### 2. Gather context (if needed)

If the user specifies a hardware requirement (e.g. "DDR5 RAM", "PCIe 4.0 NVMe"), trust their spec. Only check the local machine if they explicitly ask to verify compatibility. Do not assume they want parts for this machine.

### 3. Search with websearch

Identify the product category. Use `websearch` for discovery:

**Broad discovery:**
```bash
scripts/websearch "wireless headphones under 100 AUD buy Australia"
```

**Store-scoped searches** (target specific stores from REFERENCE.md):
```bash
scripts/websearch "wireless headphones site:amazon.com.au OR site:jbhifi.com.au OR site:scorptec.com.au"
```

**Structured extraction** (when you want to parse results programmatically):
```bash
scripts/websearch -j "DDR5-5600 32GB RAM kit Australia"
```

Each result includes: title, URL, description (HTML tags stripped). Build the comparison table directly from these fields.

Repeat with varied queries to cover different stores and product variants.

**Free shipping:** If an item's price meets a store's free shipping threshold (see REFERENCE.md), treat shipping as free. Do not assume any paid membership (e.g. Amazon Prime).

### 4. Deep-dive with Playwright (optional)

If `websearch` results lack sufficient detail (missing prices, specs, stock status, shipping info), use Playwright MCP to scrape individual store pages:

1. `browser_navigate` to the product page URL from `websearch` results
2. `browser_wait_for` — wait for content to load (especially Scorptec, PCCG — JS-heavy)
3. `browser_snapshot` or `browser_evaluate` to extract structured product data
4. Follow the [fallback hierarchy](REFERENCE.md) if extraction fails (selectors → innerText → snapshot → webfetch)

This step is optional. Skip it if `websearch` results already provide enough detail for the comparison table.

### 5. Interventions (Playwright only)

When using Playwright and you hit a CAPTCHA, login wall, or age verification:
1. Stop browsing
2. Tell the user: "I need you to handle a [CAPTCHA/login] in the browser window"
3. Wait for user confirmation
4. Continue with `browser_snapshot`

### 6. Present results

Output a markdown comparison table (all prices AUD):

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |

Sort by best value (price + rating + availability + shipping).

### 7. Agent feedback

After presenting results, briefly note:
- Any difficulties encountered (missing prices, blocked queries, sparse results)
- Whether Playwright was needed or `websearch` alone sufficed
- Suggestions for improving this skill, scripts, or workflow
- Stores that would be useful to add

### 8. Follow-up

User may ask to narrow results, check more stores, open product pages, or compare products.

## Review Checklist

- [ ] Pre-flight check passed (websearch functional)
- [ ] `websearch` used for initial product discovery
- [ ] At least 2 stores represented in results (AU storefronts first)
- [ ] All prices in AUD
- [ ] Free shipping noted where threshold is met (no membership assumptions)
- [ ] Playwright used only when websearch results were insufficient (or not at all)
- [ ] User pinged for any CAPTCHA/login walls (Playwright only)
- [ ] Compatibility checked only if user explicitly asked
- [ ] No purchase actions taken — only research and price comparison
- [ ] Agent feedback on workflow improvements included
