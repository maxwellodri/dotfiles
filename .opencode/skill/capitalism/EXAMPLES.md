# Examples

## Example 1: Simple Product Search

**User:** "find me wireless headphones under $100"

**Agent does:**
1. Runs pre-flight check
2. Navigates to Google Shopping AU: `https://www.google.com.au/search?q=wireless+headphones+under+100&tbm=shop`
3. Snapshots page, extracts top results
4. Checks Amazon AU and JB Hi-Fi for same query
5. Notes free shipping thresholds where applicable
6. Presents:

| Product | Price (AUD) | Shipping | Rating | Availability | Store | Link |
|---------|-------------|----------|--------|--------------|-------|------|
| Sony WH-CH720N | $128.00 | Free (over $49) | 4.6/5 | In stock | Amazon AU | [link](https://...) |
| Anker Soundcore Q30 | $79.99 | $9.95 | 4.5/5 | In stock | Amazon AU | [link](https://...) |
| JBL Tune 770NC | $129.00 | Free (over $50) | 4.4/5 | In stock | JB Hi-Fi | [link](https://...) |

**Agent feedback:** "JB Hi-Fi's site uses a JS-heavy search that was slow to scrape. Could add a helper script for common AU stores. Harvey Norman blocked the initial snapshot — may need to wait longer for page load."

---

## Example 2: Hardware Upgrade (User-Specified Specs)

**User:** "find me 32GB DDR5-5600 RAM kit"

**Agent does:**
1. Runs pre-flight check
2. Trusts user's spec (DDR5-5600, 32GB) — does not check local machine
3. Searches Scorptec, PCCaseGear, Umart, Amazon AU for DDR5-5600 32GB kits
4. Presents:

| Product | Price (AUD) | Shipping | Speed | CAS Latency | Availability | Store | Link |
|---------|-------------|----------|-------|-------------|--------------|-------|------|
| G.Skill Flare X5 32GB DDR5-5600 | $129.00 | $10.00 | 5600MHz | CL36 | In stock | Scorptec | [link](https://...) |
| Corsair Vengeance 32GB DDR5-5600 | $134.00 | Free (over $100) | 5600MHz | CL36 | In stock | PCCaseGear | [link](https://...) |
| Kingston Fury Beast 32GB DDR5-5600 | $119.00 | $8.50 | 5600MHz | CL38 | In stock | Umart | [link](https://...) |

**Agent feedback:** "All three AU PC stores had good structured data. Scorptec's search sometimes returns 2x16GB kits when searching for 32GB — added 'kit' to the query to filter. No international stores checked as DDR5 is widely available in AU."

---

## Example 3: PC Game

**User:** "find me the cheapest price for Baldur's Gate 3"

**Agent does:**
1. Runs pre-flight check
2. Navigates to IsThereAnyDeal: `https://isthereanydeal.com/search/?q=baldurs+gate+3`
3. Extracts prices across stores, noting Steam/GOG preference
4. Presents:

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
1. Runs pre-flight check
2. Searches Google Shopping AU (no dedicated store for this)
3. Presents whatever AU sources carry it (health food stores, online grocers, Amazon AU)

---

## Example 5: Intervention Flows

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
