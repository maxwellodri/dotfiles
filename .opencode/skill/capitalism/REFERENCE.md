# Reference

## Store Categories

### Tech / General

| Store | Search URL | Free Shipping | Notes |
|-------|-----------|---------------|-------|
| Amazon AU | `https://www.amazon.com.au/s?k={query}` | $49+ (no Prime assumption) | Use `img[alt]` for product names, `data-asin` for links |
| Scorptec | `https://www.scorptec.com.au/search/go?w={query}&view=grid&cnt=30` | $100+ | JS-heavy, use `innerText` parsing |
| PCCaseGear | `https://www.pccasegear.com/search?query={query}` | $50+ | Very JS-heavy, may need `browser_wait_for` |
| Umart | `https://www.umart.com.au/search?q={query}` | TBD | AU PC parts |
| eBay AU | `https://www.ebay.com.au/sch/i.html?_nkw={query}` | Varies | |
| JB Hi-Fi | `https://www.jbhifi.com.au/search?q={query}` | TBD | AU tech/entertainment |
| Harvey Norman | `https://www.harveynorman.com.au/search?q={query}` | TBD | AU general retailer |
| Mwave | **Unreliable** | — | URL structure broken/changed; skip for now |
| Google Shopping AU | `https://www.google.com.au/search?q={query}&tbm=shop` | N/A | Broad discovery aggregator |

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

No dedicated stores — use Google Shopping AU as primary discovery for items like vital wheat gluten, specialty flours, etc.

### International (fallback only)

Use only if item is unavailable in Australia or inherently international (e.g. Valve Index).

| Store | URL | Notes |
|-------|-----|-------|
| Amazon US | `https://www.amazon.com/s?k={query}` | Note international shipping |
| B&H Photo | `https://www.bhphotovideo.com/c/search?q={query}` | Ships to AU |
| Newegg | `https://www.newegg.com/p/pl?d={query}` | Ships to AU |

Always note international shipping costs and import considerations.

## Store Extraction Tips

### Amazon AU

- **Product name:** `img.s-image[alt]` — the `h2` element shows only the brand name
- **Price:** `.a-price .a-offscreen`
- **Link/ID:** `data-asin` attribute on `[data-component-type="s-search-result"]`
- **URL pattern:** `https://www.amazon.com.au/dp/{asin}`

```javascript
document.querySelectorAll('[data-component-type="s-search-result"]').forEach(el => {
  const name = el.querySelector('img.s-image')?.getAttribute('alt');
  const price = el.querySelector('.a-price .a-offscreen')?.textContent;
  const asin = el.getAttribute('data-asin');
  // ...
});
```

### Scorptec

- **URL:** Must use `/search/go?w={query}&view=grid&cnt=30` (NOT `/search?query=`)
- **Extraction:** JS rendering hides DOM from `querySelectorAll` — use `document.body.innerText` and parse line-by-line
- **Category URLs:** Change frequently, avoid hardcoding — use search instead

```javascript
const lines = document.body.innerText.split('\n').map(l => l.trim()).filter(l => l);
for (let i = 0; i < lines.length; i++) {
  if (lines[i].toLowerCase().includes('target keyword')) {
    // lines[i] = name, lines[i+1] = price, lines[i+2] = sale price, lines[i+3] = stock
  }
}
```

### PCCaseGear

- **Very JS-heavy** — products may not appear in DOM even after `browser_navigate`
- Use `browser_wait_for` with text selector before snapshotting
- If products still don't load, fall back to Google Shopping AU with `site:pccasegear.com`
- Category filter URLs don't work via direct navigation

### Google Shopping AU

- Broad discovery tool — use as first stop to find which stores stock an item
- Results in `div.sh-dgr__content` or similar — use `browser_snapshot` to discover actual containers
- Good for finding items that are hard to locate on individual store sites

## Playwright MCP Tools

### Navigation and Reading

| Tool | When to use |
|------|-------------|
| `browser_navigate` | Go to any URL |
| `browser_snapshot` | Read page structure (accessibility tree) |
| `browser_wait_for` | Wait for JS-heavy content to load — always use after navigate on Scorptec/PCCG |
| `browser_tabs` | Open/close/switch between store tabs |

### Interaction

| Tool | When to use |
|------|-------------|
| `browser_click` | Click search buttons, filters, "load more" |
| `browser_type` | Type into search fields |
| `browser_select_option` | Select dropdown filters |

### Data Extraction

| Tool | When to use |
|------|-------------|
| `browser_evaluate` | Run JS to extract structured data — primary extraction tool |
| `browser_take_screenshot` | Visual debugging when snapshot is unclear |

## Extraction Fallback Hierarchy

When `browser_evaluate` with selectors fails:

1. **`browser_evaluate` with selectors** — preferred, structured data
2. **`document.body.innerText` parsing** — for JS-heavy sites where DOM is hidden (Scorptec)
3. **`browser_snapshot` + manual reading** — for pages where evaluate returns empty
4. **`webfetch`** — last resort, no JS rendering but sometimes works for simple pages

## Local Spec Gathering

Only use if the user explicitly asks to verify compatibility with this machine.

```bash
sudo dmidecode -t memory   # RAM (type, speed, slots, max)
sudo dmidecode -t baseboard  # Motherboard
lscpu                      # CPU
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT  # Storage
lspci                      # PCIe slots
```

## Playwright MCP Config

Uses a config file for launch options: `.opencode/skill/capitalism/playwright-config.json`

```json
{
  "outputDir": "/home/maxwell/.cache/playwright-mcp",
  "browser": {
    "launchOptions": {
      "headless": false,
      "executablePath": "/usr/bin/chromium",
      "args": ["--disable-gpu", "--disable-dev-shm-usage"]
    }
  }
}
```

`opencode.json` MCP entry:

```json
"playwright": {
  "type": "local",
  "command": [
    "npx", "@playwright/mcp@latest",
    "--config", "/path/to/.opencode/skill/capitalism/playwright-config.json"
  ],
  "enabled": false
}
```

User enables manually via opencode TUI when needed (MCPs are context-heavy).

**Note:** The ungoogled-chromium-bin AUR package installs with restrictive `750` permissions on `/usr/bin/chromium` and `/usr/lib/chromium/`. A pacman hook at `system_configs/etc/pacman.d/hooks/ungoogled-chromium-permissions.hook` auto-fixes this on install/upgrade.
