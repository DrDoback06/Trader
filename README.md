# Trader — UK TCG Arbitrage Decision-Support

Find **underpriced trading cards on eBay UK**, value them against real UK sold prices,
rank them by **profit after fees**, and get alerted to buy the best ones — manually.
Pokémon first; built to extend to Lorcana / One Piece / MTG.

> **Decision-support, not auto-buying.** eBay does not grant automated-purchase API
> access to small operators, and bot-buying breaches eBay's User Agreement. So the bot does
> the hard 99% — find → identify → value → score → rank → alert with a one-tap buy link —
> and **you click buy** (a 5-second step). The reselling side can be automated later via
> eBay's Sell APIs.

## How it works

```
eBay UK active listings        →  identify the exact card + condition  (the #1-risk step)
   (Browse API, Phase 2)             ↓
                                  value it vs eBay UK SOLD prices       (3rd-party API, Phase 3)
                                     ↓
                                  profit after UK fees → score × confidence → your buy rules
                                     ↓
                                  ranked deals on the dashboard + alerts → you buy manually
```

The whole pipeline runs **offline on bundled sample data in Phase 1** (no API keys, no cost),
so you can see and trust the money logic before wiring in live data.

## Run it

> 🆕 **New to all this?** Read [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) — a
> dummy-proof, step-by-step guide to getting every API key and the app fully running.

**Quickstart — one command** (creates the venv, installs deps, builds the dashboard, serves it):

```bash
./run.sh        # → http://localhost:8000   (add --catalogue to import the full set list first)
```

Then open **http://localhost:8000** and paste your keys under **Sources & Keys** — each input has a
"where to get this ↗" link. Or do it step by step:

```bash
# 1. Backend deps
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/pytest                       # full test suite (network disabled for the core)

# 2. (Recommended) Import the FULL Pokémon catalogue (~20k cards, every set).
#    Run locally — pokemontcg.io must be reachable. A free key raises rate limits.
POKEMONTCG_API_KEY=optional .venv/bin/python -m trader.tools.import_pokemontcg

# 3. Build the dashboard (the backend then serves it too)
npm --prefix frontend install
npm --prefix frontend run build

# 4. Run everything as one process
.venv/bin/uvicorn trader.main:app --app-dir backend     # open http://localhost:8000
```

Then in the browser:
1. **Sources & Keys** → paste your eBay keys + RapidAPI key (each has a "where to get this" link).
2. **Deals** → choose **Everything (scour eBay)** and an *ending-within* window → **Run live eBay scan**.
3. Deals are ranked best-first with green/amber/red **profit** and **sell-through** lights and a
   one-tap **Open ↗** link to buy.

Without keys you'll still see ranked **demo** deals (bundled sample data) so you can try the UI.

**Dev mode** (hot-reload frontend on :5173, backend on :8000):
`npm --prefix frontend run dev` + `.venv/bin/uvicorn trader.main:app --reload --app-dir backend`.

API: `GET /deals`, `GET/PUT /settings`, `GET /sources` + `PUT /sources/credentials`,
`GET /watchlist`, `GET /quota`, `POST /scan` `{mode, ending_within_hours}`, `GET /health`.

## What's built (Phase 1 ✅)

- **Pure-logic core** (`backend/trader/core/`): `Money` (Decimal, currency-safe), a config-driven
  UK **fee/economics** model, **confidence** scoring, deal **scoring/ranking**, and the **rules
  engine** (budget, per-card cap, min profit/ROI/margin/confidence, graded policy, language,
  red-flag exclusions). Fully unit-tested with **no network**.
- **Identifier** (`backend/trader/identify/`): parses titles/specifics → set, number, finish,
  language, grade; matches to a card **catalogue**; flags proxies/lots/damage; emits a match
  confidence. Conservative by design — it would rather miss a deal than buy a dud.
- **Triage indicators** (`core/rating.py`): a **traffic-light profit tier** (GREEN/AMBER/RED by
  ROI) shown alongside the ROI%, a **market-discount %**, and a **sell-through probability**
  (liquidity + price stability) with its own traffic light — so high-margin-but-illiquid cards
  are visibly distinguished from quick, reliable flips. Sell-through also factors into ranking.
- **Pipeline + providers**: swappable provider interfaces with offline fixture implementations,
  so the engine runs end-to-end without keys.
- **FastAPI** app serving ranked deals + a **React/TypeScript dashboard**.

## What's built (Phase 2 ✅ — live eBay UK scanning)

- **eBay Browse client** (`providers/ebay_browse.py` + `ebay_oauth.py`): OAuth client-credentials
  with token caching, `EBAY_GB` marketplace, `item_summary/search` with UK/price/buying-option
  filters, mapped to the same `ListingFacts` the engine already understands.
- **Quota-aware scanner** (`services/scanner.py` + `quota.py` + `dedup.py`): runs a prioritized
  `WatchTarget` list within a daily call budget, de-duplicates, and feeds the pipeline.
- **Discovery / "scour" mode**: instead of naming cards, sweep a whole category for the
  **cheapest Buy-It-Now & Best-Offer** listings, or **auctions ending soon** (1/2/3/6/12h window),
  and let the engine surface the underpriced ones. The identifier turns a broad sweep into
  per-card deals. (Coverage scales with the card catalogue — see the roadmap.)
- **`POST /scan`** runs it live when eBay keys are set (`EBAY_CLIENT_ID/SECRET`, `EBAY_ENV`);
  without keys it returns a clear message. Sandbox-first via `EBAY_ENV=sandbox`.
## What's built (Phase 3 ✅ — live UK valuation + in-UI keys)

- **Live eBay-UK sold prices** (`providers/soldprice_rapidapi.py`): real avg/median UK sold
  values via a swappable `SoldPriceProvider`, behind a **cache-first** wrapper (`valuation.py`) so
  a repeat lookup costs nothing.
- **Sources & Keys page**: paste your API keys in the UI (with "where to get this" links), and
  tick which price sources to use. Only sources we trust for the **UK** can be enabled —
  **eBay UK sold** (value) and **eBay UK active** (discovery). **Cardmarket** (EU, API closed) and
  **PriceCharting** (US, USD) are shown for transparency but can't be turned on, since EU/US prices
  would mislead a UK strategy. Keys are stored locally (gitignored, masked on read), applied
  instantly — no restart.
- A **Run live eBay scan** button on the Deals page kicks off a real scan once keys are set.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for Phases 2–6 (live scanning, valuation, alerts,
portfolio, reselling) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design.

## Tech

Python 3.11 · FastAPI · Pydantic · rapidfuzz · pytest/ruff/mypy · Vite + React + TypeScript.

## ⚠️ Disclaimer

This tool provides **decision-support only**. It does not buy anything. You are responsible for
your own purchases, for compliance with eBay's terms, and for any **UK tax** obligations —
systematic buy-to-resell is treated as **trading income** by HMRC, and regular reselling likely
makes you a **business seller** on eBay. Estimated values and fee rates are configurable
approximations, not guarantees. This is not financial, legal, or tax advice.
