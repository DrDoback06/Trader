# Roadmap

Status: **Phase 1 complete.** Phases 2+ require external API keys / accounts.

## Phase 1 — Pure-logic core + skeleton (no API keys) ✅
Economics, confidence, scoring, rules, catalogue, identifier — all unit-tested with network
disabled. Pipeline runs offline on bundled sample data. FastAPI serves ranked demo deals; React
dashboard renders them. **Done.**

## Phase 2 — Live eBay Browse scanning (quota-aware) ✅ (in-memory)
- ✅ `providers/ebay_oauth.py` (cached client-credentials token) + `providers/ebay_browse.py`
  (`X-EBAY-C-MARKETPLACE-ID: EBAY_GB`, `item_summary/search`, explicit `buyingOptions`, GB filters).
- ✅ `services/quota.py` (≤ ~5,000 calls/day budget) + `services/scanner.py` over a prioritized
  `WatchTarget` list; `services/dedup.py` (id + title/seller/price fingerprint).
- ✅ `POST /scan`, `GET /watchlist`, `GET /quota`; `respx` integration tests (request shape,
  token caching, dedup, quota stop) + sandbox base-URL switch via `EBAY_ENV`.
- ✅ **Discovery / "scour" mode:** `ScanMode` (WATCH / CHEAPEST / ENDING_SOON) lets a target sweep
  a whole category (no keyword) for cheapest BIN/Best-Offer (`sort=price`) or auctions ending
  within a window (`itemEndDate` filter + `sort=endingSoonest`). `POST /scan` takes
  `{mode, ending_within_hours}`; the UI exposes mode + a 1/2/3/6/12h dropdown.
- ⏳ **Deferred to Phase 4:** persisting `Listing` / `ScanJob` (SQLAlchemy + Alembic) and a
  scheduled (APScheduler) recurring scan — currently a single on-demand in-memory scan.
- ✅ **Full catalogue importer:** `python -m trader.tools.import_pokemontcg` pulls every set/card
  from pokemontcg.io into a gitignored `catalogue_data/imported/` that the app auto-prefers. The
  matcher uses a name-token index so it stays fast at ~20k cards. (Run locally — the API host is
  blocked in some sandboxes.) Seed sets remain for offline demo/tests.
- **To go live:** set `EBAY_CLIENT_ID/SECRET` (+ `EBAY_ENV`) and GB trading-card category ids.

## Phase 3 — Live sold-price valuation ✅
- ✅ `providers/soldprice_rapidapi.py` (`findCompletedItems`, `site_id=3` UK, outlier exclusion,
  graded-grade keywords) + `services/valuation.py` cache-first wrapper with TTL (cache hit = zero
  HTTP calls). Confidence + sell-through fed by the real sample size / spread.
- ✅ **In-UI key entry + source registry:** `GET/PUT /sources` lets you paste keys (applied at
  runtime, stored in gitignored `.trader/credentials.json`, masked on read) and toggle sources.
  Only UK-accurate sources are usable (eBay UK sold + active); Cardmarket (EU, API closed) and
  PriceCharting (US) are listed but cannot be enabled.
- ✅ `providers/factory.py` selects the live provider when configured + enabled, else the fixture.
- **To go live:** add your RapidAPI key under **Sources & Keys** in the UI (~£10–40/mo).

## Phase 4 — Alerting + persistence hardening ⏳
- `providers/alert_telegram.py` with an inline buy button; idempotent `Alert`
  (unique `(channel, dedup_key)`); Postgres; `Deal` lifecycle (NEW→ALERTED→DISMISSED/BOUGHT).
- **Verify:** same deal twice ⇒ one message; SQLite→Postgres migration; deep-link correctness.
- **Needs:** `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`.

## Phase 5 — Portfolio / positions / ledger (limit & stop-loss) ⏳
- `Position` from "mark bought"; `LedgerEntry`; realized/unrealized P&L; `services/portfolio.py`
  evaluates **limit** (target resale) and **stop-loss** (floor + `max_days_held`) → reprice /
  cut-loss suggestions; CSV export for HMRC.
- **Verify:** P&L + trigger unit tests with `freezegun`; PortfolioPage shows holdings + actions.

## Phase 6 — Reselling automation (seam only) 🔒
Future `SellExecutor` over eBay Sell Inventory/Trading to auto-list/reprice. The `BuyExecutor`
stays a no-op. Position/Ledger/limit/stop-loss fields are the forward-compatible seam.

## Cross-cutting backlog
- AMBIGUOUS review queue in the dashboard (cheap accuracy gains, feeds catalogue corrections).
- Optional PriceCharting (USD, FX-adjusted) cross-check behind `SoldPriceProvider`.
- Add Lorcana / One Piece / MTG catalogues + per-game condition/grade normalization.
- Image-based identification for listings with weak titles.
