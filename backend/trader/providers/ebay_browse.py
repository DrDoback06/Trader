"""eBay Browse API client (implements the ``ListingSource`` interface).

Searches active UK listings via ``item_summary/search`` with the
``X-EBAY-C-MARKETPLACE-ID: EBAY_GB`` header. Supports keyword searches, whole-
category sweeps (no ``q``), auction end-time windows (``itemEndDate`` filter), and
sort orders including ``endingSoonest`` — so the scanner can both watch specific
cards and "scour" a category for the best deals.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx

from ..core.models import BuyingFormat, ListingFacts
from ..core.money import Money
from .ebay_oauth import EbayOAuth

_MAX_LIMIT = 200


def _ebay_ts(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M:%S.000Z")


class EbayBrowseSource:
    def __init__(
        self,
        oauth: EbayOAuth,
        browse_base: str,
        *,
        marketplace_id: str = "EBAY_GB",
        client: httpx.Client | None = None,
    ) -> None:
        self._oauth = oauth
        self._base = browse_base.rstrip("/")
        self._marketplace = marketplace_id
        self._client = client or httpx.Client(timeout=20.0)

    def fetch(
        self,
        *,
        query: str | None = None,
        limit: int = 50,
        offset: int = 0,
        category_ids: Sequence[str] | None = None,
        buying_options: Sequence[str] = ("FIXED_PRICE",),
        max_price: float | None = None,
        condition_ids: Sequence[str] | None = None,
        item_location_country: str = "GB",
        item_end_within_hours: float | None = None,
        sort: str | None = "newlyListed",
    ) -> list[ListingFacts]:
        if not query and not category_ids:
            raise ValueError("Browse search needs a query or category_ids")

        filters: list[str] = []
        if buying_options:
            filters.append("buyingOptions:{" + "|".join(buying_options) + "}")
        if max_price is not None:
            filters.append(f"price:[..{max_price}]")
            filters.append("priceCurrency:GBP")
        if condition_ids:
            filters.append("conditionIds:{" + "|".join(condition_ids) + "}")
        if item_location_country:
            filters.append(f"itemLocationCountry:{item_location_country}")
        if item_end_within_hours is not None:
            now = datetime.now(UTC)
            end = now + timedelta(hours=item_end_within_hours)
            filters.append(f"itemEndDate:[{_ebay_ts(now)}..{_ebay_ts(end)}]")

        params: dict[str, str] = {"limit": str(min(limit, _MAX_LIMIT))}
        if query:
            params["q"] = query
        if offset:
            params["offset"] = str(offset)
        if category_ids:
            params["category_ids"] = ",".join(category_ids)
        if filters:
            params["filter"] = ",".join(filters)
        if sort:
            params["sort"] = sort

        resp = self._client.get(
            f"{self._base}/item_summary/search",
            params=params,
            headers={
                "Authorization": f"Bearer {self._oauth.token()}",
                "X-EBAY-C-MARKETPLACE-ID": self._marketplace,
                "Content-Type": "application/json",
            },
        )
        resp.raise_for_status()
        data = resp.json()
        return [self._to_listing(it) for it in data.get("itemSummaries", [])]

    @staticmethod
    def _to_listing(it: dict[str, Any]) -> ListingFacts:
        price = it.get("price") or {}

        shipping: Money | None = None
        options = it.get("shippingOptions") or []
        if options:
            cost = options[0].get("shippingCost") or {}
            if cost.get("value") is not None:
                shipping = Money.of(cost["value"], cost.get("currency", "GBP"))

        buying = it.get("buyingOptions") or []
        fmt = (
            BuyingFormat.AUCTION
            if "AUCTION" in buying and "FIXED_PRICE" not in buying
            else BuyingFormat.FIXED_PRICE
        )

        categories = it.get("categories") or []
        category_id = categories[0].get("categoryId") if categories else None

        return ListingFacts(
            external_id=str(it.get("itemId", "")),
            title=it.get("title", ""),
            price=Money.of(price.get("value", "0"), price.get("currency", "GBP")),
            source="EBAY",
            shipping=shipping,
            item_specifics={},  # detailed aspects require the item endpoint, not search
            buying_format=fmt,
            condition_raw=it.get("condition"),
            seller=(it.get("seller") or {}).get("username"),
            item_location_country=(it.get("itemLocation") or {}).get("country", "GB"),
            category_id=category_id,
            url=it.get("itemWebUrl"),
            image_url=(it.get("image") or {}).get("imageUrl"),
            item_end_date=it.get("itemEndDate"),
        )
