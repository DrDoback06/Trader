"""Quota-aware scanner.

Runs watch targets against a listing source, de-duplicates, then pushes the new
listings through the pipeline into ranked deals. Each target can be a specific
card search (WATCH) or a whole-category "scour" (CHEAPEST / ENDING_SOON), and may
sweep several pages within the daily call budget.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

import httpx

from ..core.models import BuyingFormat, Card, Deal, ListingFacts, ScanMode, Valuation, WatchTarget
from ..identify.catalogue import Catalogue
from ..providers.base import ListingSource, SoldPriceProvider
from ..providers.ebay_errors import ebay_error_detail
from .dedup import Dedup
from .pipeline import PipelineConfig, run_pipeline
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
    # Per-target failures (e.g. eBay 403 on a category sweep) — collected rather than
    # raised, so one bad target doesn't throw away the deals other targets found.
    errors: list[str] = field(default_factory=list)


def _target_label(target: WatchTarget) -> str:
    if target.query:
        return f'"{target.query}"'
    cats = ",".join(target.category_ids) or "all"
    return f"{target.mode} sweep (category {cats})"


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


class _NoSoldPrices:
    """A sold-price provider that values nothing — lets us still emit (unvalued) deals
    when the real sold-price service is down, so the user at least sees the listings."""

    name = "none"

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        return None


_NO_SOLD_PRICES = _NoSoldPrices()


def _valuation_error(exc: httpx.HTTPError) -> str:
    if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code in (401, 403):
        return (
            "sold-price valuation unavailable — your RapidAPI key was rejected (401/403); "
            "check it's correct and subscribed to the eBay Average Selling Price API"
        )
    return f"sold-price valuation unavailable — couldn't reach the service ({exc})"


def _ask_key(listing: ListingFacts) -> float:
    """What you'd pay now (current bid for auctions, else price) + postage."""
    base = (
        listing.current_bid_price
        if listing.buying_format is BuyingFormat.AUCTION and listing.current_bid_price is not None
        else listing.price
    )
    ship = float(listing.shipping.amount) if listing.shipping is not None else 0.0
    return float(base.amount) + ship


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

            try:
                listings = source.fetch(offset=page * target.limit, **kwargs)
            except httpx.HTTPStatusError as exc:
                detail = ebay_error_detail(exc) or f"HTTP {exc.response.status_code}"
                result.errors.append(f"{_target_label(target)}: {detail}")
                break  # skip this target's remaining pages; keep scanning the rest
            except httpx.HTTPError as exc:
                result.errors.append(f"{_target_label(target)}: could not reach eBay ({exc})")
                break

            result.listings_seen += len(listings)
            for listing in listings:
                if dedup.is_new(listing):
                    new_listings.append(listing)

            if len(listings) < target.limit:
                break  # last page reached

        if result.quota_exhausted:
            break

    result.new_listings = len(new_listings)
    # Cost guard: value only the cheapest N new listings (the likeliest steals); the
    # rest wait for a later scan (each valuation caches once fetched, so this is cheap).
    to_value = new_listings
    if max_valuations and len(to_value) > max_valuations:
        to_value = sorted(to_value, key=_ask_key)[:max_valuations]
    try:
        result.deals = run_pipeline(to_value, catalogue, sold_provider, cfg)
        result.valued = len(to_value)
        result.unvalued = len(new_listings) - len(to_value)
    except httpx.HTTPError as exc:
        # The sold-price service failed (e.g. RapidAPI key rejected). Still return the
        # listings we found — unvalued — so the user sees them, with a clear reason.
        result.errors.append(_valuation_error(exc))
        result.deals = run_pipeline(to_value, catalogue, _NO_SOLD_PRICES, cfg)
        result.valued = 0
        result.unvalued = len(new_listings)
    return result
