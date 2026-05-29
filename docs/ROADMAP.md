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

## Phase 4 / Wave 1 #1 — Alerting + scheduled auto-scans + persistence ✅
- ✅ SQLAlchemy persistence (`db/`), idempotent `AlertRow` (unique `(channel, dedup_key)`).
- ✅ `providers/alert_telegram.py` + `services/alerts.py` (top deals, dedup); `services/scheduler.py`
  (APScheduler) runs the "everything" scan every `SCAN_INTERVAL_MIN`; `POST /alerts/test`, `GET /alerts`.
- ✅ Verified end-to-end (mocked): same deal twice ⇒ exactly one Telegram message.
- ⏳ **Later:** Alembic migrations + Postgres in prod; `Deal` lifecycle (NEW→ALERTED→DISMISSED/BOUGHT);
  inline buy button.
- **To enable:** set `SCAN_INTERVAL_MIN>0`, `ALERT_CHANNEL=telegram`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

## Wave 1 also delivered
- #2 annualised-ROI + sold-velocity ranking; #4 low-/no-bid auction data + max-bid solver;
  #7 Best-Offer/auction acquisition pricing.

## Wave 2 — big-margin tactics ✅
- #5 grading arbitrage (`core/economics.GradingProfile` + `compute_grading_economics`);
  #6 misspelling/vague-title hunter (`services/typos.py`, `hidden_gems` mode);
  #3 price-trend/hype momentum (`PriceSnapshotRow` + `services/trends.py`).

## Wave 3 — depth ✅ (Phase 5 + more)
- #9 capital allocator (`core/allocator.py`) + portfolio P&L (`PositionRow`, `services/portfolio.py`,
  `/allocate`, `/portfolio`, Portfolio dashboard tab, "📌 Bought"/"Mark sold").
- #8 graded + sealed scan modes (catalogue-free title valuation, flagged UNVERIFIED).
- #10 vision card ID from photos (`providers/vision_claude.py`, Claude API, `[vision]` extra) —
  reads the card off the image then re-matches the catalogue; opt-in via the `vision` source.

## Phase 6 — Reselling automation ✅ (compliant, preview-first)
- `services/relist.py` builds an accurate listing draft (honest title/condition/description;
  never reuses the source photos); `providers/ebay_sell.py` lists via the eBay **Inventory API**
  (createOrReplaceInventoryItem → createOffer → publishOffer) on the seller's own account.
- `POST /portfolio/{id}/relist` is **preview-first**: returns a draft; publishes only with
  `publish=true` + your own `image_urls` + configured seller token/policies. Dashboard "Relist"
  button shows the draft. Buying stays manual (`BuyExecutor` no-op) — only selling is automated.
- **To enable:** `EBAY_USER_TOKEN` (sell.inventory scope) + business-policy IDs + location key;
  see `docs/DEPLOY.md` → Relisting.
- ⏳ **Later:** in-app OAuth refresh flow; auto-reprice / relist-on-buy toggle; offer-exists (409)
  → updateOffer.

## Cross-cutting backlog
- AMBIGUOUS review queue in the dashboard (cheap accuracy gains, feeds catalogue corrections).
- Optional PriceCharting (USD, FX-adjusted) cross-check behind `SoldPriceProvider`.
- Add Lorcana / One Piece / MTG catalogues + per-game condition/grade normalization.
- Image-based identification for listings with weak titles.
