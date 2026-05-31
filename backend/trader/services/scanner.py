"""Quota-aware scanner.

Runs watch targets against a listing source, de-duplicates, then pushes the new
listings through the pipeline into ranked deals. Each target can be a specific
card search (WATCH) or a whole-category "scour" (CHEAPEST / ENDING_SOON), and may
sweep several pages within the daily call budget.

:func:`scan` powers the category sweeps (Discovery): it identifies each listing
from its own title. :func:`search_card` powers card search: it fetches listings
for one typed card and values them all against that *known* card, so they come
back priced instead of blank.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from ..core.models import BuyingFormat, Card, Deal, ListingFacts, ScanMode, WatchTarget
from ..core.scoring import rank_deals
from ..identify.catalogue import Catalogue
from ..providers.base import ListingSource, SoldPriceProvider
from .dedup import Dedup
from .pipeline import PipelineConfig, evaluate_against_card, run_pipeline
from .quota import DailyQuota


@dataclass
class ScanResult:
    targets_scanned: int = 0
    calls_used: int = 0
    listings_seen: int = 0
    new_listings: int = 0
    valued: int = 0
    unvalued: int = 0
    quota_exhausted: bool = False
    deals: list[Deal] = field(default_factory=list)


def _fetch_kwargs(target: WatchTarget) -> dict[str, Any]:
    base: dict[str, Any] = {
        "limit": target.limit,
        "category_ids": list(target.category_ids) or None,
        "condition_ids": list(target.condition_ids) or None,
        "max_price": target.max_price,
    }
    if target.mode is ScanMode.CHEAPEST:
        return {
            **base,
            "query": target.query or None,
            "buying_options": target.buying_options or ("FIXED_PRICE", "BEST_OFFER"),
            "sort": target.sort or "price",
        }
    if target.mode is ScanMode.ENDING_SOON:
        return {
            **base,
            "query": target.query or None,
            "buying_options": ("AUCTION",),
            "item_end_within_hours": target.ending_within_hours or 12,
            "sort": target.sort or "endingSoonest",
        }
    return {
        **base,
        "query": target.query,
        "buying_options": target.buying_options,
        "sort": target.sort or "newlyListed",
    }


def _ask_key(listing: ListingFacts) -> float:
    """What you'd pay now (current bid for auctions, else price) + postage."""
    base = (
        listing.current_bid_price
        if listing.buying_format is BuyingFormat.AUCTION and listing.current_bid_price is not None
        else listing.price
    )
    ship = float(listing.shipping.amount) if listing.shipping is not None else 0.0
    return float(base.amount) + ship


def _collect_new_listings(
    targets: Sequence[WatchTarget],
    source: ListingSource,
    *,
    quota: DailyQuota,
    dedup: Dedup,
    result: ScanResult,
) -> list[ListingFacts]:
    """Fetch + de-duplicate within the daily call budget, updating ``result`` counters."""
    ordered = sorted((t for t in targets if t.enabled), key=lambda t: t.priority, reverse=True)
    new_listings: list[ListingFacts] = []

    for target in ordered:
        if not quota.can_spend(1):
            result.quota_exhausted = True
            break
        result.targets_scanned += 1
        kwargs = _fetch_kwargs(target)

        for page in range(max(1, target.pages)):
            if not quota.can_spend(1):
                result.quota_exhausted = True
                break
            quota.spend(1)
            result.calls_used += 1

            listings = source.fetch(offset=page * target.limit, **kwargs)
            result.listings_seen += len(listings)
            for listing in listings:
                if dedup.is_new(listing):
                    new_listings.append(listing)

            if len(listings) < target.limit:
                break  # last page reached

        if result.quota_exhausted:
            break

    result.new_listings = len(new_listings)
    return new_listings


def scan(
    targets: Sequence[WatchTarget],
    source: ListingSource,
    catalogue: Catalogue,
    sold_provider: SoldPriceProvider,
    *,
    quota: DailyQuota,
    dedup: Dedup | None = None,
    cfg: PipelineConfig | None = None,
    max_valuations: int = 0,
) -> ScanResult:
    cfg = cfg or PipelineConfig()
    dedup = dedup or Dedup()
    result = ScanResult()

    new_listings = _collect_new_listings(targets, source, quota=quota, dedup=dedup, result=result)

    # Cost guard: value only the cheapest N new listings (the likeliest steals); the
    # rest wait for a later scan (each valuation caches once fetched, so this is cheap).
    to_value = new_listings
    if max_valuations and len(to_value) > max_valuations:
        to_value = sorted(to_value, key=_ask_key)[:max_valuations]
    result.valued = len(to_value)
    result.unvalued = len(new_listings) - len(to_value)
    result.deals = run_pipeline(to_value, catalogue, sold_provider, cfg)
    return result


def search_card(
    query: str,
    card: Card,
    source: ListingSource,
    sold_provider: SoldPriceProvider,
    *,
    quota: DailyQuota,
    cfg: PipelineConfig | None = None,
    dedup: Dedup | None = None,
    max_price: float | None = None,
    limit: int = 100,
    pages: int = 1,
    category_ids: tuple[str, ...] = (),
) -> ScanResult:
    """Card search: fetch live listings for one typed card and value them all
    against that *known* ``card`` (clean identity), dropping wrong variants.

    Unlike :func:`scan`, every kept listing is valued — there's no per-listing cost
    blow-up because the sold-price lookup caches per (card, condition), so a hundred
    listings cost only a handful of sold-price calls.
    """
    cfg = cfg or PipelineConfig()
    dedup = dedup or Dedup()
    result = ScanResult()

    target = WatchTarget(
        query=query,
        mode=ScanMode.WATCH,
        category_ids=category_ids,
        buying_options=("FIXED_PRICE", "BEST_OFFER", "AUCTION"),
        sort="price",
        max_price=max_price,
        limit=limit,
        pages=pages,
    )
    new_listings = _collect_new_listings([target], source, quota=quota, dedup=dedup, result=result)

    deals: list[Deal] = []
    for listing in new_listings:
        deal = evaluate_against_card(listing, card, sold_provider, cfg)
        if deal is not None:  # None => dropped (wrong variant / hard red flag)
            deals.append(deal)

    result.valued = sum(1 for d in deals if d.valuation is not None)
    result.unvalued = len(deals) - result.valued
    result.deals = rank_deals(deals)
    return result
