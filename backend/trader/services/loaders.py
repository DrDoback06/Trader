"""Helpers to build domain objects from plain dicts / JSON."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..core.models import BuyingFormat, ListingFacts
from ..core.money import Money


def listing_from_dict(d: dict[str, Any]) -> ListingFacts:
    shipping = d.get("shipping")
    return ListingFacts(
        external_id=str(d["external_id"]),
        title=d["title"],
        price=Money.gbp(d["price"]),
        source=d.get("source", "EBAY"),
        shipping=Money.gbp(shipping) if shipping is not None else None,
        item_specifics=d.get("item_specifics") or {},
        buying_format=BuyingFormat(d.get("buying_format", "FIXED_PRICE")),
        condition_raw=d.get("condition_raw"),
        seller=d.get("seller"),
        item_location_country=d.get("item_location_country", "GB"),
        category_id=d.get("category_id"),
        url=d.get("url"),
        image_url=d.get("image_url"),
    )


def load_listings(path: str | Path) -> list[ListingFacts]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return [listing_from_dict(d) for d in data]
