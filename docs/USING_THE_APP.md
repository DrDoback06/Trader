# Using Trader — the dummy's guide

A plain-language tour of the app once it's running and your keys are in. **The golden
rule:** the bot finds, identifies, values, scores and ranks deals — **you click buy.** It
never spends your money. Selling (relisting) can be automated later, but buying is always you.

---

## The four tabs

| Tab | What it's for |
|-----|---------------|
| **Deals** | Scan eBay UK for underpriced cards, and "Check a card" by hand. The main money screen. |
| **Browse** | Flip through the catalogue (set → cards) and tap a card to value it. |
| **Portfolio** | Your holdings (Set → Card → each copy), P&L, and relist/mark-sold. |
| **Sources & Keys** | Paste API keys and switch price sources on/off. |

---

## Your daily flow (Deals tab)

1. **Pick a scan mode** (the "Scan" dropdown):
   - **Everything (scour eBay)** — the broad sweep; best default.
   - **Cheapest BIN & offers** — lowest Buy-It-Now / Best-Offer prices.
   - **Auctions ending soon** — pick a window (1–12h) to catch last-minute steals.
   - **Hidden gems (typos)** — misspelled/vague titles others miss.
   - **Graded slabs (PSA/CGC)** — slabbed cards, tuned for long-term holds.
   - **Sealed boxes / ETBs** — sealed product.
   - **My watchlist cards** — your specific searches.
2. Click **↻ Run live eBay scan**. The bot pulls listings, identifies each card, values it
   against real eBay-UK **sold** prices, works out profit after fees, and ranks them.
3. **Filter & sort like eBay** (the bar above the table): sort by *best / ending soonest /
   price / ROI / biggest discount / sell-through*; filter by *buying type*, *condition*,
   and *max price*.
4. **Open ↗** takes you to the eBay listing to **buy it yourself**. Then hit **📌 Bought**
   to drop it into your Portfolio.

> Cost control: each scan only fetches a live value for the **cheapest ~250** new listings
> (the likeliest steals) and caches them, so you stay on a cheap sold-price plan. Re-scans
> are nearly free because values are cached for 72h.

---

## Reading a deal row

| Column | Meaning |
|--------|---------|
| **Card** | The identified card (+ set/number). Badges: 🔼 *grade-and-flip*, 💎 *hold*, 🔥/🔻 *momentum*, plus flags (LOT, DAMAGED, VISION…). |
| **Cond.** | Raw condition (NM/LP/…) or the grade (PSA 10). |
| **Type** | **BIN**, **BIN + Offer**, or **Auction** (auctions show time-left). |
| **Ask** | What you'd pay now (current bid for auctions) + postage. |
| **Est. value** | Market value from real UK sold prices; `n=` is how many sales it's based on. |
| **Profit** | Expected profit after all fees. |
| **ROI** 🟢🟡🔴 | Return on investment. Green = high. `≈x/yr` = annualised (adjusts for how fast it sells). |
| **Disc.** | How far below market you're buying. |
| **Sell-through** 🟢🟡🔴 | Rough chance it sells near market (liquidity + price stability). `~Nd` = est. days to sell. |
| **Match** | How confident the ID is. Low = treat with care. |
| **Status** | **BUY** (clears your rules) or **skip** (hover for the reason). |

**The mental model:** 🟢 ROI **and** 🟢 sell-through = a quick, reliable flip. 🟢 ROI but
🔴 sell-through = big margin that may sit a while (fine if you're patient). 💎 Hold = a
graded slab below market worth sitting on.

The **"Only deals that clear my buy rules"** checkbox hides everything that fails your
limits (budget, min profit/ROI/margin, confidence, etc.).

---

## Check a card (works without the eBay listing key)

Top of the Deals tab. Type a card the way you'd search eBay (e.g. `Charizard ex 199/165`,
or `Pikachu 173/165 PSA 10`) and the price you'd pay → **Check value**. You get a real
verdict on live sold prices — handy to sanity-check a listing you're looking at on eBay.
Hit **📌 Bought** on the result to track it.

---

## Browse (catalogue)

Set tiles → every card in the set (in number order) with a name/number filter → **tap a
card** to jump to *Check a card* with it pre-filled. Right now it shows the bundled sample
sets; run `./run.bat --catalogue` once (ideally on a stable connection) to load **every
set + card images**.

---

## Portfolio

- **Best buys for your budget** — enter your capital (e.g. £300) and **Recommend** picks the
  basket that maximises expected profit within budget.
- **Holdings** — nested **Set → Card → each copy**, with its condition/grade, status
  (HELD / LISTED / SOLD), what you paid, current value (or sold price), and **P/L**, plus
  per-set subtotals and overall invested / unrealised / realised figures.
- Per copy: **Relist** (builds an eBay listing draft — preview first), **Mark sold** (record
  the sale price), **Open ↗** (the original listing).

---

## Sources & Keys

Paste keys (applied instantly, stored locally) and tick the sources you trust. The two that
matter: **eBay UK — Sold prices** (RapidAPI; your market values) and **eBay UK — Active
listings** (your eBay Client ID/Secret; the listings to scan). **Photo ID (Claude)** is
optional. **eBay relist (Sell API)** needs the seller token — see below.

---

## Optional: turn on auto-relisting (the seller token)

You **don't need this** to find, buy, and track cards — it only automates the *selling* step.
When you're ready:

1. In your **eBay seller account**, set up **business policies** (payment, return, postage)
   and an **inventory location** — eBay requires these to list via the API
   (Seller Hub → Account → Business policies).
2. Mint a **user OAuth token** with the `sell.inventory` scope (this authorises listing on
   *your* account — different from the Client ID/Secret, which are app keys):
   eBay Developer Portal → your **Production** keyset → **User Tokens** → **"Get a Token from
   eBay via Your Application"** (OAuth). You'll set a Redirect URL (RuName) once, then sign in
   with your selling account and consent. Paste the returned token into **eBay seller token**
   and tick **eBay relist (Sell API)**.
3. Relisting is **preview-first**: it builds an accurate draft (your own photos, honest
   title/condition) and only publishes when you confirm — so you stay within eBay's rules.

> Portal-minted tokens last ~2 hours (fine to test). For hands-off relisting we can add an
> in-app "Connect eBay" button that handles consent + auto-refresh — ask when you want it.

---

## Staying out of trouble
- **You buy manually** — no bot purchasing (that breaches eBay's rules).
- Relist only cards you **own**, with **your own photos** and **accurate** descriptions.
- As a reseller you're a **business seller** (returns/consumer rights) and the profit is
  **taxable** (HMRC trading income). Estimated values/fees are approximations — sanity-check
  big buys.
