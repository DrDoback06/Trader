# Architecture

## Principle: a pure core behind swappable I/O

The money-making logic is a set of **pure functions over plain data** with zero I/O and zero
third-party imports, so it is exhaustively unit-testable with the network disabled. Everything
external (eBay, sold-price data, alerts, buying) sits behind **Protocol interfaces** and is
injected, so live implementations can be added or mocked without touching the engine.

```
backend/trader/
  core/        money, models, economics, confidence, scoring, rules   (PURE — no I/O, no keys)
  identify/    parser, grading, normalize, catalogue, matcher          (PURE + catalogue files)
  providers/   base (interfaces) + fixture/console/no-op impls         (I/O lives here)
  services/    pipeline, loaders, demo                                 (orchestration)
  api/         FastAPI routers + serialize                             (HTTP)
  catalogue_data/  seed card data (JSON)
  sample_data/     demo listings + sold prices (offline run)
frontend/      Vite + React + TypeScript dashboard
tests/         unit/ (network-disabled), e2e/ (offline pipeline)
```

## The pipeline (`services/pipeline.py`)

For each listing: `parse → normalize condition → identify → value → economics → confidence →
score → rules.evaluate → Deal`, then `rank_deals`. It is pure orchestration over injected
providers, so it behaves identically on fixtures (Phase 1) and live data (Phases 2–3).

## Key design decisions

- **`Money` is `Decimal` + currency.** No floats for money; cross-currency requires an explicit
  `convert(rate, ...)` so GBP/USD can never be silently mixed (matters once a USD source is added).
- **Fees are config-driven** (`FeeProfile`) — no magic numbers in the maths. UK 2024–25 defaults
  are documented estimates and trivially overridable (incl. a `is_business_seller` flag).
- **Score = risk-adjusted profit** (`profit × confidence`); a big nominal margin on a shaky match
  must not outrank a solid, well-identified flip.
- **Identification is conservative** — hard flags (proxy/fake/lot) reject outright; near-tie
  candidates are `AMBIGUOUS`; graded-vs-raw bucket mismatch collapses confidence. Bias toward
  false negatives (miss a deal) over false positives (buy a dud).
- **No automated buying.** `BuyExecutor` is a deliberate no-op seam (`providers/buy_noop.py`).

## Data model (core entities)

`Card` (catalogue) · `WatchTarget` (Phase 2) · `ListingFacts` · `Identification` · `Valuation` ·
`FeeProfile` · `RuleSet` · `Deal` · `ScanJob` (Phase 2) · `Alert` (Phase 4) · `Position`/`Ledger`
(Phase 5). Phase 1 models live in `core/models.py`; persistence (SQLAlchemy) arrives in Phase 2.

## Forward-compatible seams

- `ListingSource` — eBay today, other marketplaces later.
- `SoldPriceProvider` — fixture now; RapidAPI/Apify (UK sold) in Phase 3; eBay Marketplace
  Insights if access is ever granted — all behind one interface.
- `AlertChannel` — console now; Telegram in Phase 4.
- `BuyExecutor` — permanent no-op unless compliant access appears.
- `FeeProfile.effective_from` — auditable fee changes over time.
- A future `Catalogue` source — seed JSON now, a live card-data API (e.g. pokemontcg.io) later.

## Identifier detail (`identify/`)

1. **parse** title + item specifics → number (`199/165`, promos), set (synonyms), name (residual),
   finish, language, grade (`PSA 10`), and red-flags.
2. **normalize** condition → `RAW_NM/LP/MP/HP/DAMAGED` (unknown ⇒ LP, conservative).
3. **match** to catalogue: candidates filtered by card number, ranked by
   `0.55·name + 0.35·number + 0.10·set` (rapidfuzz). Threshold ⇒ `MATCHED` / `AMBIGUOUS` /
   `REJECTED`.
4. **confidence** = `match × f(sample_size) × g(spread) × penalty(soft_flags)`.
