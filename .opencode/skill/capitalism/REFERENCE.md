# Reference

## Store Categories

### Tech / General

| Store | URL | Notes |
|-------|-----|-------|
| Google Shopping AU | `https://www.google.com.au/search?q={query}&tbm=shop` | Broad discovery, always start here |
| Amazon AU | `https://www.amazon.com.au/s?k={query}` | Check free shipping threshold |
| eBay AU | `https://www.ebay.com.au/sch/i.html?_nkw={query}` | |
| JB Hi-Fi | `https://www.jbhifi.com.au/search?q={query}` | AU tech/entertainment retailer |
| Harvey Norman | `https://www.harveynorman.com.au/search?q={query}` | AU general retailer |
| Scorptec | `https://www.scorptec.com.au/search?q={query}` | AU PC parts |
| PCCaseGear | `https://www.pccasegear.com.au/search?q={query}` | AU PC parts |
| Umart | `https://www.umart.com.au/search?q={query}` | AU PC parts |

### PC Games

| Store | URL | Notes |
|-------|-----|-------|
| IsThereAnyDeal | `https://isthereanydeal.com/search/?q={query}` | Primary for PC game price comparison |
| Green Man Gaming | `https://www.greenmangaming.com/search?q={query}` | Secondary |
| Humble Store | `https://www.humblebundle.com/store/search?q={query}` | Secondary |

**Game preference:** Steam or GOG keys preferred if cost is same. User plays on PC only.

### Books

| Store | URL | Notes |
|-------|-----|-------|
| Angus & Robertson | `https://www.angusrobertson.com.au/search?q={query}` | AU bookstore |
| QBD | `https://www.qbd.com.au/search?q={query}` | AU bookstore |
| Amazon AU | `https://www.amazon.com.au/s?k={query}` | Also has books |

### Food / Specialty Ingredients

No dedicated stores — use Google Shopping AU as primary discovery for items like vital wheat gluten, specialty flours, etc. Local grocery delivery sites may appear in search results.

### International (fallback only)

Use only if item is unavailable in Australia or inherently international (e.g. Valve Index).

| Store | URL | Notes |
|-------|-----|-------|
| Amazon US | `https://www.amazon.com/s?k={query}` | Note international shipping |
| B&H Photo | `https://www.bhphotovideo.com/c/search?q={query}` | Ships to AU |
| Newegg | `https://www.newegg.com/p/pl?d={query}` | Ships to AU |

Always note international shipping costs and import considerations when presenting international results.

## Playwright MCP Tools

### Navigation and Reading

| Tool | When to use |
|------|-------------|
| `browser_navigate` | Go to any URL |
| `browser_snapshot` | Read page structure (accessibility tree). Always use after navigate |
| `browser_wait_for` | Wait for dynamic content to load |
| `browser_tabs` | Open/close/switch between store tabs |

### Interaction

| Tool | When to use |
|------|-------------|
| `browser_click` | Click search buttons, filters, "load more" |
| `browser_type` | Type into search fields |
| `browser_select_option` | Select dropdown filters (sort by price, etc.) |

### Data Extraction

| Tool | When to use |
|------|-------------|
| `browser_evaluate` | Run JS to extract structured data. Primary tool for pulling prices/ratings |
| `browser_take_screenshot` | Visual debugging when snapshot is unclear |

## Price Extraction Strategies

After navigating to a search results page, use `browser_snapshot` to understand the page structure, then `browser_evaluate` to extract data.

### Generic extraction pattern

```javascript
// Adapt selectors based on what browser_snapshot reveals
const products = [];
document.querySelectorAll('SELECTOR').forEach(el => {
  products.push({
    name: el.querySelector('TITLE_SELECTOR')?.textContent?.trim(),
    price: el.querySelector('PRICE_SELECTOR')?.textContent?.trim(),
    rating: el.querySelector('RATING_SELECTOR')?.textContent?.trim(),
    link: el.querySelector('LINK_SELECTOR')?.href,
  });
});
return JSON.stringify(products.filter(p => p.name && p.price));
```

**Important:** Selectors vary by store. Always `browser_snapshot` first to discover the actual DOM structure before writing extraction JS.

### Google Shopping AU extraction

Google Shopping results are typically in `div.sh-dgr__content` or similar. Use snapshot to find the actual container, then extract title, price, and merchant links.

## Local Spec Gathering

Only use if the user explicitly asks to verify compatibility with this machine.

```bash
sudo dmidecode -t memory   # RAM (type, speed, slots, max)
lshw -class display        # GPU
lscpu                      # CPU
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT  # Storage
sudo dmidecode -t baseboard  # Motherboard
lspci                      # PCIe slots
uname -r                   # Kernel version
```

## Playwright MCP Config

Configured in `.config/opencode/opencode.json`:

```json
"playwright": {
  "type": "local",
  "command": [
    "npx", "@playwright/mcp@latest",
    "--executable-path", "/usr/bin/ungoogled-chromium"
  ],
  "enabled": false
}
```

User enables manually via opencode TUI when needed (MCPs are context-heavy even when inactive).
