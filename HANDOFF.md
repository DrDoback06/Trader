# Handoff — Trader deal-finding upgrades

Branch: **`claude/bold-feynman-umcqr`** (3 commits on top of `764a0f2`).
24 files changed, +1467 / -46. Backend tests: 206 pass (1 pre-existing flake in
`test_relist.py`, unrelated to this work — it fails because `test_api_scan` mutates
`app.state.deals` before it; present on the base branch too).

This document is everything needed to integrate these changes into another copy of
the app. Each section says **what changed, why, and the exact integration point**.

---

## TL;DR — what this branch adds

1. **Three user-reported blockers fixed** (add-to-list buried, Browse had no options,
   ROIs blank with no explanation).
2. **Keyless valuation fallback** — flips the default provider to the chain so the free
   pokemontcg.io source values raw cards with no key, plus a new Claude rough-estimate
   rung for graded slabs / niche cards.
3. **Hidden Gems** — a new "value vs. attention" ranking axis + page + `/gems` endpoint.
4. **Sniper sub-tab** — auctions ending ≤2h, server-filtered.
5. **Misspell sweep** — optional typo fan-out on the batch scan.
6. **Same-origin API fix** — dashboard worked on `localhost` only; now works on any host.

---

## Commit 1 — `9fa9942` "Make today work"

### Backend

**`backend/trader/providers/soldprice_vision.py`** (NEW)
- `ClaudeEstimateProvider` — a `SoldPriceProvider` (same `get_valuation(card, condition_key)`
  protocol as the others). Last-resort rung: when sold comps + pokemontcg both miss
  (typically graded slabs, which pokemontcg returns `None` for), it asks Claude for a
  single GBP estimate.
- Returns a `Valuation` with `provider="claude_estimate"`, small `sample_size` (3) and a
  wide baseline `spread` (0.45) so confidence stays honestly low.
- Never raises — missing SDK or any API error returns `None` so the chain just falls through.
- Pure helper `_parse_response()` extracts `{median_gbp, low_gbp, high_gbp}` from Claude's
  reply, tolerant of extra prose.

**`backend/trader/providers/factory.py`** — in `build_sold_provider()`, append
`ClaudeEstimateProvider` to the chain when source `vision_estimate` is enabled and
`anthropic_api_key` is configured. Order is RapidAPI → pokemontcg → claude_estimate → fixture.

**`backend/trader/services/sources.py`** — new `SourceInfo` entry `vision_estimate`
(role "Market value", requires `anthropic_api_key`, `default_enabled=False`).

**`backend/trader/api/catalogue.py`** — `set_cards` now joins each card with
`app.state.card_insights[card_id]` and returns extra fields: `market_value`, `gem_score`,
`active_listings_count`, `trend_pct`, `attention_delta_7d` (all `null` until a scan
populates them). This is what drives the Browse-tile badges.

**`backend/trader/api/serialize.py`** — `deal_to_dict` emits `gem_score`,
`active_listings_count`, `watchers`, `attention_delta_7d`.

> NOTE: in commit 1 these fields were read via `getattr`/an `_insights` shim; commit 2
> adds the real `Deal` fields and the serializer reads them directly. If integrating
> piecemeal, take the commit-2 version of `serialize.py` and `models.py` together.

### Frontend

**`frontend/src/components/ValuationStatusBanner.tsx`** (NEW) — reads `/sources`, renders a
banner above the Deals table stating exactly which valuation source is active
(🔴 none / ⚠️ free-only / ⚠️ vision-only / 💚 eBay sold on). Returns `null` while loading
or on error (never blocks the page).

**`frontend/src/components/DealsTable.tsx`**
- `whyNoValuation(deal)` — returns the human reason a row is `—` (graded slab needs RapidAPI /
  no comps in 90 days / waiting on re-scan). Every `—` is wrapped in `<span class="why" title=…>`.
- `valuationLabel(deal)` — tags rows: `est. (rough)` for `claude_estimate`, `ref` for
  `pokemontcg_market`.
- New **Gem** column (💎 score + 🏷️ active-listing count).
- New **Watch** toggle in the actions column (props `watched: Set<string>`,
  `onToggleWatch(query, on)`).

**`frontend/src/components/DealsPage.tsx`**
- Mounts `<ValuationStatusBanner/>`.
- `watched` set + `toggleWatch` passed to every `<DealsTable>`.
- The buried "➕ List" link is now a primary **★ Watch this card** button.
- `hideSamples` only flips once a scan returns `valued > 0` (an empty scan no longer
  blanks the screen).

**`frontend/src/components/BrowsePage.tsx`**
- Per-tile **☆/★ Watch** button (calls `addCard`/`removeCard`) with a fading toast.
- New controls: **Sort** (number / name / value / gem / rarity), **Rarity** filter,
  **💎 Gems only** toggle.
- Tile badges: 💰 market value, 🔥/🔻 trend, 🏷️ active listings, 💎 gem.

**`frontend/src/types.ts`** — added `gem_score`, `active_listings_count`, `watchers`,
`attention_delta_7d` to `Deal`; value/gem/trend fields to `CatalogueCard`; new `GemCard`.

**`frontend/src/api.ts`** — `fetchGems()`.

**`frontend/src/styles.css`** — `.banner*`, `.why`, `.valbadge`, `.watchbtn*`, `.badge-*`,
`.gemchip`, `.watchtoast` (all reuse existing CSS vars; no new colour tokens).

### Tests
**`tests/unit/test_soldprice_vision.py`** — 9 tests: response parsing + SDK-patched
end-to-end + graceful miss when SDK absent.

---

## Commit 2 — `16cd666` "Find more deals"

### Backend

**`backend/trader/core/scoring.py`** — `compute_gem_score(...)`:
```
gem_score = (estimated_value × confidence)
          ÷ (1 + active_listings + √(sample_size + 1))   # saturation penalty
          × (1 + max(trend_pct, 0))                       # rising-price bonus
          × max(sell_probability, 0.1)                    # liquidity floor (niche still ranks)
          × (1 + clamp(attention_delta_7d, 0..1))         # external attention
          × max(0.25, 1 − watchers/50)                    # watcher penalty, floored
```
Returns 0 if value or confidence ≤ 0. Missing signals (watchers/attention None) are neutral.

**`backend/trader/core/models.py`** — `Deal` gains `gem_score`, `active_listings_count`,
`watchers`, `attention_delta_7d`.

**`backend/trader/services/pipeline.py`** — computes `deal.gem_score` right after `deal.score`,
feeding the valuation/confidence/sell-probability it already has.

**`backend/trader/api/gems.py`** (NEW)
- `GET /gems?limit&set_code&min_value` — returns cards ranked by gem_score from
  `app.state.card_insights`. Works between scans (doesn't need live deals).
- `update_card_insights(app, deals)` — folds each scan's deals into the persistent
  `app.state.card_insights` map (median, cheapest listing, listing count, gem score per
  card). **Call this anywhere you set `app.state.deals` after a scan.**

**`backend/trader/api/deals.py`** — `GET /deals` gains `mode` + `within_hours`:
- `mode=sniper` → only auctions ending within `within_hours` (default 2) with positive bid
  floor, sorted by end time.
- `mode=gems` → deals with `gem_score > 0`, sorted desc.

**`backend/trader/api/scan.py`** — `CardsScanIn` gains `include_misspellings`; batch scan
passes it through to the existing `_card_targets` typo fan-out; both scan paths now call
`update_card_insights(...)`.

**`backend/trader/identify/catalogue.py`** — `Catalogue.get(card_id)` (id→Card lookup, used
by `/gems`).

**`backend/trader/main.py`** — registers `gems_api.router`; initialises
`app.state.card_insights = {}`.

### Frontend

**`frontend/src/components/HiddenGemsPage.tsx`** (NEW) — the 💎 Gems page. Min-value filter,
top-N selector, tile grid; tapping a tile prefills Deals and runs the live search.

**`frontend/src/App.tsx`** — new `💎 Gems` nav tab + `gems` view.

**`frontend/src/api.ts`** — `fetchDeals(onlyPassing, {mode, withinHours})`;
`scanCards` + `CardsScanOptions` gain `include_misspellings`.

**`frontend/src/components/DealsPage.tsx`** — `🔤 Misspell sweep` toggle;
`All deals | ⏳ Sniper (≤2h)` tab row that re-fetches with `mode`.

### Tests
**`tests/unit/test_gem_score.py`** — 14 tests across every multiplier (saturation, trend,
liquidity floor, watcher penalty + floor, attention clamp, neutral-when-missing).

---

## Commit 3 — `db04537` "Same-origin fetch fix"

**`frontend/src/api.ts`** — `API_BASE` default changed from `"http://localhost:8000"` to `""`.
The backend serves the built dashboard from the same process, so same-origin fetches work on
any host (server IP, tunnel, LAN). `VITE_API_BASE` is still honoured for split dev
(`:5173` frontend + `:8000` API). **This is the fix for "failed to fetch" on a remote server.**

---

## Integration checklist for the other copy

If the other version is a *fork* of the same codebase, the cleanest path is to merge the
branch. If you're hand-porting:

1. **Take these whole new files** (no merge conflict risk):
   - `backend/trader/providers/soldprice_vision.py`
   - `backend/trader/api/gems.py`
   - `frontend/src/components/ValuationStatusBanner.tsx`
   - `frontend/src/components/HiddenGemsPage.tsx`
   - `tests/unit/test_gem_score.py`, `tests/unit/test_soldprice_vision.py`

2. **Add the `Deal` fields** (`models.py`) and the **`compute_gem_score`** function
   (`scoring.py`) — everything else depends on these. Then wire the pipeline call.

3. **Register the router + state** in `main.py`: `app.include_router(gems_api.router)` and
   `app.state.card_insights = {}`.

4. **Call `update_card_insights(app, deals)`** wherever the app stores scan results into
   `app.state.deals`. (In this branch: both code paths in `api/scan.py`.)

5. **Frontend**: add the nav tab in `App.tsx`, the new fields in `types.ts`, the new
   functions in `api.ts`, the CSS block, and the component edits to
   `DealsPage`/`DealsTable`/`BrowsePage`.

6. **Config default**: confirm the sold-price provider resolves to the *chain* (RapidAPI →
   pokemontcg → claude → fixture) so keyless users get raw-card values. In this codebase the
   chain is assembled in `providers/factory.py:build_sold_provider`; `sources.py` ships
   `pokemontcg_market` with `default_enabled=True`.

7. **Don't forget commit 3** — set `API_BASE` default to `""` or the dashboard breaks on any
   non-localhost host.

## Verify after integrating

```bash
.venv/bin/pytest                 # or .venv\Scripts\pytest on Windows
npm --prefix frontend run build  # tsc --noEmit must pass clean
```

Then run the app and check: Browse tiles show a value with no keys; the Deals banner names
the active source; every `—` has a tooltip; the 💎 Gems tab and ⏳ Sniper tab load.

## New / changed HTTP surface

| Method | Path | Change |
| --- | --- | --- |
| GET | `/deals?mode=sniper&within_hours=2` | new `mode` (`all`/`sniper`/`gems`) + `within_hours` |
| GET | `/gems?limit&set_code&min_value` | **new** — cards ranked by gem_score |
| GET | `/catalogue/sets/{code}/cards` | response gains value/gem/trend/listing fields |
| POST | `/scan/cards` | body gains `include_misspellings: bool` |
| (deal JSON) | everywhere deals serialize | gains `gem_score`, `active_listings_count`, `watchers`, `attention_delta_7d` |

## Known follow-ups (NOT built — scoped in the plan, left for later)

- `active_listings_count` / `watchers` / `attention_delta_7d` are **plumbed but not yet
  populated** — the eBay Browse client doesn't yet capture the search `total` or fetch
  per-listing watcher counts, and there's no attention feed (pokemontcg.io views / Google
  Trends) job. Until those land, gem_score is driven by value × confidence ÷ √sample_size
  and the listing-saturation term stays 0. Wiring them is the bulk of the original PR-3 plan.
- Lot decomposer and grading-arbitrage queue from the plan were not started.
