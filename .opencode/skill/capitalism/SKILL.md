---
name: capitalism
description: Search for products, compare prices across stores, check availability, and find compatible hardware using browser automation. Use when the user asks to go shopping or find items to buy.
---

# Capitalism

## Defaults

- **Currency:** AUD
- **Region:** Australia, Brisbane (for shipping purposes)
- **Stores:** Australian storefronts first; international only if item is unavailable in AU or inherently international (e.g. Valve hardware)
- **Read-only:** NEVER purchase, add to cart, or submit any order. The agent finds the best deals and presents links — user buys manually.

## Terminology

- **product query** — what the user wants to find (can be vague: "RAM to upgrade to 64GB")
- **intervention** — agent pauses browsing and pings user to handle CAPTCHA, login, or age verification in the visible browser window
- **comparison table** — markdown table with product, price (AUD), rating, availability, store, link

## Quick Start

1. User describes what they need: "find me wireless headphones under $100"
2. Run `scripts/capitalism_check.sh` — if it fails, stop and show remediation
3. Verify Playwright MCP tools are available — if not, remind user to enable MCP and restart
4. Search Google Shopping AU, then category-appropriate AU stores
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

If check passes but Playwright MCP tools are not available, tell user to enable the playwright MCP and restart opencode.

### 2. Gather context (if needed)

If the user specifies a hardware requirement (e.g. "DDR5 RAM", "PCIe 4.0 NVMe"), trust their spec. Only check the local machine if they explicitly ask to verify compatibility. Do not assume they want parts for this machine.

### 3. Search and scrape

Identify the product category and pick appropriate stores from [REFERENCE.md](REFERENCE.md). Use Australian storefronts by default.

Core loop:
1. `browser_navigate` to store search URL
2. `browser_wait_for` — wait for content to load (especially Scorptec, PCCG — JS-heavy)
3. `browser_snapshot` or `browser_evaluate` to extract structured product data
4. If extraction fails, follow the [fallback hierarchy](REFERENCE.md) (selectors → innerText → snapshot → webfetch)
5. Repeat across stores

**Free shipping:** If an item's price meets a store's free shipping threshold, treat shipping as free. Do not assume any paid membership (e.g. Amazon Prime).

### 4. Interventions

When you hit a CAPTCHA, login wall, or age verification:
1. Stop browsing
2. Tell the user: "I need you to handle a [CAPTCHA/login] in the browser window"
3. Wait for user confirmation
4. Continue with `browser_snapshot`

### 5. Present results

Output a markdown comparison table (all prices AUD):

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |

Sort by best value (price + rating + availability + shipping).

### 6. Agent feedback

After presenting results, briefly note:
- Any difficulties encountered (broken selectors, blocked scrapes, missing stores)
- Suggestions for improving this skill, scripts, or workflow
- Stores that would be useful to add

### 7. Follow-up

User may ask to narrow results, check more stores, open product pages, or compare products.

## Review Checklist

- [ ] Pre-flight check passed
- [ ] At least 2 stores checked (AU storefronts first)
- [ ] All prices in AUD
- [ ] Free shipping noted where threshold is met (no membership assumptions)
- [ ] User pinged for any CAPTCHA/login walls
- [ ] Compatibility checked only if user explicitly asked
- [ ] No purchase actions taken — only research and price comparison
- [ ] Agent feedback on workflow improvements included
