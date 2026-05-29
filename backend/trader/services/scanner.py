"""Quota-aware scanner: run watch targets against a listing source, de-duplicate,
then push the new listings through the pipeline into ranked deals."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field

from ..core.models import Deal, WatchTarget
from ..identify.catalogue import Catalogue
from ..providers.base import ListingSource, SoldPriceProvider
from .dedup import Dedup
from .pipeline import PipelineConfig, run_pipeline
from .quota import DailyQuota


@dataclass
class ScanResult:
    targets_scanned: int = 0
    calls_used: int = 0
    listings_seen: int = 0
    new_listings: int = 0
    quota_exhausted: bool = False
    deals: list[Deal] = field(default_factory=list)


def scan(
    targets: Sequence[WatchTarget],
    source: ListingSource,
    catalogue: Catalogue,
    sold_provider: SoldPriceProvider,
    *,
    quota: DailyQuota,
    dedup: Dedup | None = None,
    cfg: PipelineConfig | None = None,
) -> ScanResult:
    cfg = cfg or PipelineConfig()
    dedup = dedup or Dedup()
    result = ScanResult()

    # Highest priority first, so a tight budget is spent on the best targets.
    ordered = sorted(
        (t for t in targets if t.enabled), key=lambda t: t.priority, reverse=True
    )

    new_listings = []
    for target in ordered:
        if not quota.can_spend(1):
            result.quota_exhausted = True
            break
        quota.spend(1)
        result.targets_scanned += 1
        result.calls_used += 1

        listings = source.fetch(
            query=target.query,
            limit=target.limit,
            category_ids=list(target.category_ids) or None,
            buying_options=target.buying_options,
            max_price=target.max_price,
            condition_ids=list(target.condition_ids) or None,
        )
        result.listings_seen += len(listings)
        for listing in listings:
            if dedup.is_new(listing):
                new_listings.append(listing)

    result.new_listings = len(new_listings)
    result.deals = run_pipeline(new_listings, catalogue, sold_provider, cfg)
    return result
