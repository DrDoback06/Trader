from __future__ import annotations

from typing import Any

import httpx
import respx

from trader.core.models import WatchTarget
from trader.providers.ebay_browse import EbayBrowseSource
from trader.providers.ebay_oauth import EbayOAuth
from trader.services.quota import DailyQuota
from trader.services.scanner import _fetch_kwargs, scan
from trader.services.watchlist import cheapest_sweep_target, ending_soon_sweep_target

OAUTH = "https://api.ebay.com/identity/v1/oauth2/token"
BROWSE = "https://api.ebay.com/buy/browse/v1"


def _item(
    item_id: str, title: str = "Pokemon 151 Charizard ex 199/165 Near Mint"
) -> dict[str, Any]:
    return {
        "itemId": item_id,
        "title": title,
        "price": {"value": "45.00", "currency": "GBP"},
        "buyingOptions": ["FIXED_PRICE"],
        "condition": "Used",
        "seller": {"username": "shop"},
        "itemLocation": {"country": "GB"},
        "categories": [{"categoryId": "183454"}],
        "itemWebUrl": f"https://www.ebay.co.uk/itm/{item_id}",
    }


@respx.mock
def test_scan_dedups_and_produces_deals(catalogue: Any, sold_provider: Any) -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    # Same item returned twice => the duplicate must be dropped.
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [_item("A"), _item("A")]})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    targets = [WatchTarget(query="charizard 199/165", category_ids=("183454",))]

    result = scan(targets, src, catalogue, sold_provider, quota=DailyQuota(10))

    assert result.calls_used == 1
    assert result.listings_seen == 2
    assert result.new_listings == 1
    assert any(d.passed_rules for d in result.deals)


def test_fetch_kwargs_per_mode() -> None:
    cheapest = _fetch_kwargs(cheapest_sweep_target())
    assert cheapest["sort"] == "price"
    assert "BEST_OFFER" in cheapest["buying_options"]
    assert cheapest["query"] is None  # category sweep, no keyword

    ending = _fetch_kwargs(ending_soon_sweep_target(ending_within_hours=3))
    assert ending["sort"] == "endingSoonest"
    assert ending["buying_options"] == ("AUCTION",)
    assert ending["item_end_within_hours"] == 3


@respx.mock
def test_sweep_paginates_within_quota(catalogue: Any, sold_provider: Any) -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [_item("A")]})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    # limit=1 and a full page each time -> keeps paginating up to `pages`
    target = WatchTarget(
        query="charizard", category_ids=("183454",), limit=1, pages=3, priority=1
    )

    result = scan([target], src, catalogue, sold_provider, quota=DailyQuota(10))
    assert result.calls_used == 3  # three pages swept


@respx.mock
def test_scan_values_only_cheapest_when_capped(catalogue: Any, sold_provider: Any) -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )

    def priced(item_id: str, value: str) -> dict[str, Any]:
        it = _item(item_id)
        it["price"] = {"value": value, "currency": "GBP"}
        return it

    priced_items = [("A", "50"), ("B", "40"), ("C", "30"), ("D", "20"), ("E", "10")]
    items = [priced(i, v) for i, v in priced_items]
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": items})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    targets = [WatchTarget(query="charizard 199/165", category_ids=("183454",))]

    result = scan(targets, src, catalogue, sold_provider, quota=DailyQuota(10), max_valuations=3)

    assert result.new_listings == 5
    assert result.valued == 3
    assert result.unvalued == 2
    # Only the three cheapest were valued (priced into deals).
    assert sorted(float(d.listing.price.amount) for d in result.deals) == [10.0, 20.0, 30.0]


@respx.mock
def test_scan_skips_failing_target_and_keeps_others(catalogue: Any, sold_provider: Any) -> None:
    # A 403 on one target (e.g. eBay rejects a category sweep) must not throw away the
    # listings other targets found — record the error and carry on.
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    respx.get(f"{BROWSE}/item_summary/search").mock(
        side_effect=[
            httpx.Response(
                403,
                json={"errors": [{"errorId": 1100, "message": "Insufficient permissions."}]},
            ),
            httpx.Response(200, json={"itemSummaries": [_item("A")]}),
        ]
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    targets = [
        WatchTarget(query="charizard", category_ids=("183454",), priority=5),
        WatchTarget(query="pikachu", category_ids=("183454",), priority=1),
    ]

    result = scan(targets, src, catalogue, sold_provider, quota=DailyQuota(10))

    assert len(result.errors) == 1
    assert "errorId 1100" in result.errors[0]
    assert result.listings_seen == 1  # second target still scoured a listing
    assert result.new_listings == 1


class _RejectingSoldProvider:
    """A sold-price provider that 401s every lookup (e.g. a bad RapidAPI key)."""

    name = "reject"

    def get_valuation(self, card: Any, condition_key: str) -> Any:
        request = httpx.Request("GET", "https://rapidapi.test/x")
        raise httpx.HTTPStatusError(
            "401", request=request, response=httpx.Response(401, request=request)
        )


@respx.mock
def test_scan_returns_unvalued_listings_when_valuation_fails(catalogue: Any) -> None:
    # eBay returns listings but the sold-price key is rejected — still surface the listings
    # (unvalued) with a clear error, instead of throwing the whole scan away.
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [_item("A")]})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    targets = [WatchTarget(query="charizard 199/165", category_ids=("183454",))]

    result = scan(targets, src, catalogue, _RejectingSoldProvider(), quota=DailyQuota(10))

    assert result.listings_seen == 1
    assert result.deals  # the listing still comes back, just unvalued
    assert result.valued == 0
    assert any("RapidAPI" in e for e in result.errors)


@respx.mock
def test_scan_stops_at_quota(catalogue: Any, sold_provider: Any) -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": []})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    targets = [WatchTarget(query="a", priority=5), WatchTarget(query="b", priority=1)]

    result = scan(targets, src, catalogue, sold_provider, quota=DailyQuota(1))

    assert result.calls_used == 1  # budget of 1 stops after the first target
    assert result.quota_exhausted is True
