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

## Quickstart (Phase 1 — no API keys needed)

### Backend

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
.venv/bin/pytest                       # 48 tests, network disabled, ~96% core coverage
.venv/bin/uvicorn trader.main:app --reload --app-dir backend   # http://localhost:8000/docs
```

Key endpoints: `GET /deals`, `GET /deals?only_passing=true`, `GET /deals/{id}`,
`GET/PUT /settings` (edit buy rules and re-rank live), `GET /health`.

### Frontend

```bash
cd frontend
npm install
npm run dev                            # http://localhost:5173 (expects backend on :8000)
```

You'll see ranked demo deals: genuine bargains flagged **BUY**, while damaged cards, joblots,
wrong-language, mis-identified, and overpriced listings are correctly filtered out with reasons.

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
