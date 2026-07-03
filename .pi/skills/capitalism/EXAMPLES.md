# Examples

## Example 1: Simple Product Search (websearch only)

**User:** "find me wireless headphones under $100"

**Agent does:**
1. Runs pre-flight check — websearch OK
2. Runs broad discovery:
   ```
   scripts/websearch "wireless headphones under 100 AUD buy Australia"
   ```
3. Runs store-scoped search:
   ```
   scripts/websearch "wireless headphones under $100 site:amazon.com.au OR site:jbhifi.com.au"
   ```
4. Builds comparison table from websearch results

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |
|---------|-------------|----------|--------|--------------|-------|------|
| Sony WH-CH720N | $128.00 | Free (over $49) | 4.6/5 | In stock | Amazon AU | [link](https://...) |
| Anker Soundcore Q30 | $79.99 | $9.95 | 4.5/5 | In stock | Amazon AU | [link](https://...) |
| JBL Tune 770NC | $129.00 | Free (over $50) | 4.4/5 | In stock | JB Hi-Fi | [link](https://...) |

**Agent feedback:** "websearch alone provided sufficient detail for all three stores. No Playwright needed. Harvey Norman didn't appear in results — could try a targeted query."

---

## Example 2: Hardware Upgrade with staticICE + Playwright

**User:** "find me 32GB DDR5-5600 RAM kit"

**Agent does:**
1. Runs pre-flight check — websearch OK, Playwright available
2. Trusts user's spec (DDR5-5600, 32GB) — does not check local machine
3. **staticICE first** — navigates to `https://www.staticice.com.au/cgi-bin/search.cgi?q=32GB+DDR5-5600`
   - Extracts `document.body.innerText.substring(0, 3000)` to get all prices across stores
   - Instantly sees cheapest prices from MSY, CPL, Scorptec, PCCG, Umart, etc.
4. Websearch for supplementary discovery (Amazon-only listings, new products)
5. If needed, Playwright deep-dive on specific store pages for specs (CAS latency, stock)
6. Presents:

| Product | Price (AUD) | Shipping | Speed | CAS Latency | Availability | Store | Link |
|---------|-------------|----------|-------|-------------|--------------|-------|------|
| G.Skill Flare X5 32GB DDR5-5600 | $129.00 | $10.00 | 5600MHz | CL36 | In stock | Scorptec | [link](https://...) |
| Corsair Vengeance 32GB DDR5-5600 | $134.00 | Free (over $100) | 5600MHz | CL36 | In stock | PCCaseGear | [link](https://...) |
| Kingston Fury Beast 32GB DDR5-5600 | $119.00 | $8.50 | 5600MHz | CL38 | In stock | Umart | [link](https://...) |

**Agent feedback:** "staticICE found the cheapest price instantly across 15+ stores. Websearch supplemented with Amazon listings. staticICE also revealed MSY had the same Kingston kit for $115 — wouldn't have found that without it."

---

## Example 3: PC Game

**User:** "find me the cheapest price for Baldur's Gate 3"

**Agent does:**
1. Runs pre-flight check — websearch OK
2. Searches IsThereAnyDeal and stores:
   ```
   scripts/websearch "Baldur's Gate 3 cheapest price Australia buy"
   ```
3. Presents:

| Store | Price (AUD equiv.) | Platform | DRM | Link |
|-------|--------------------|----------|-----|------|
| Steam | $89.95 | Steam | Steam | [link](https://...) |
| GOG | $89.95 | GOG | DRM-free | [link](https://...) |
| Green Man Gaming | $71.99 | Steam key | Steam | [link](https://...) |
| Humble Store | $71.99 | Steam key | Steam | [link](https://...) |

**Note:** Green Man Gaming and Humble have Steam keys at the best price. Steam and GOG are same price — GOG is DRM-free if that matters to you.

---

## Example 4: Specialty Food Ingredient

**User:** "find me vital wheat gluten"

**Agent does:**
1. Runs pre-flight check — websearch OK
2. Broad search:
   ```
   scripts/websearch "vital wheat gluten buy Australia"
   ```
3. Presents whatever AU sources appear (health food stores, online grocers, Amazon AU)

---

## Example 5: Intervention Flows (Playwright only)

### CAPTCHA
1. Agent detects CAPTCHA page via `browser_snapshot`
2. Agent tells user: "I hit a CAPTCHA on [store]. Please solve it in the ungoogled-chromium window, then let me know."
3. User solves CAPTCHA, confirms: "done"
4. Agent runs `browser_snapshot` and continues

### Login Wall
1. Agent detects login requirement (page shows "sign in to continue" or similar)
2. Agent tells user: "[Store] requires login. Please sign in via the browser window, then let me know."
3. User logs in, confirms: "done"
4. Agent continues scraping with authenticated session

---

## Example 6: Preserving Un-extractable Pages as Open Tabs

**User:** "find me a 27" 4K monitor under $500"

**Agent does:**
1. Runs pre-flight — websearch OK, Playwright available
2. staticICE search for "27 inch 4K monitor" — gets broad pricing
3. websearch for supplementary discovery
4. Tries Playwright deep-dive on a few top results
5. On Scorptec page, extraction works fine (innerText parsing)
6. On Harvey Norman page, all extraction methods fail (JS-heavy, image-based pricing, anti-bot)

**Agent handles the failed page:**
1. Runs `browser_tabs` — opens a new tab
2. Navigates new tab to the next product page
3. Leaves Harvey Norman tab open with the product page visible
4. Continues research on other products

**Comparison table includes:**

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |
|---------|-------------|----------|--------|--------------|-------|------|
| LG 27UL850 | $449.00 | Free | 4.7/5 | In stock | Scorptec | [link](https://...) |
| Dell S2722QC | $399.00 | Free | 4.5/5 | In stock | Amazon AU | [link](https://...) |
| Samsung S27A600U | ⚠ manual review | TBD | — | — | Harvey Norman | [link](https://...) |

**Agent feedback:** "1 product page left open in browser for manual review (Harvey Norman — extraction failed due to JS-heavy layout). websearch + staticICE covered everything else."
