from __future__ import annotations

from decimal import Decimal

import httpx
import respx

from trader.core.models import BuyingFormat
from trader.providers.ebay_browse import EbayBrowseSource
from trader.providers.ebay_oauth import EbayOAuth

OAUTH = "https://api.ebay.com/identity/v1/oauth2/token"
BROWSE = "https://api.ebay.com/buy/browse/v1"

_ITEM = {
    "itemId": "v1|1234|0",
    "title": "Pokemon 151 Charizard ex 199/165 Near Mint",
    "price": {"value": "45.00", "currency": "GBP"},
    "shippingOptions": [{"shippingCost": {"value": "1.55", "currency": "GBP"}}],
    "buyingOptions": ["FIXED_PRICE"],
    "condition": "Used",
    "seller": {"username": "cardshop"},
    "itemLocation": {"country": "GB"},
    "categories": [{"categoryId": "183454"}],
    "itemWebUrl": "https://www.ebay.co.uk/itm/1234",
    "image": {"imageUrl": "https://i.ebayimg.com/x.jpg"},
}


@respx.mock
def test_fetch_builds_uk_request_and_parses() -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "TKN", "expires_in": 7200})
    )
    route = respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [_ITEM]})
    )

    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE, marketplace_id="EBAY_GB")
    listings = src.fetch(
        query="charizard 199/165", max_price=60, buying_options=("FIXED_PRICE", "AUCTION")
    )

    req = route.calls.last.request
    assert req.headers["X-EBAY-C-MARKETPLACE-ID"] == "EBAY_GB"
    assert req.headers["Authorization"] == "Bearer TKN"
    flt = req.url.params["filter"]
    assert "buyingOptions:{FIXED_PRICE|AUCTION}" in flt
    assert "itemLocationCountry:GB" in flt
    assert "price:[..60]" in flt
    assert req.url.params["q"] == "charizard 199/165"

    assert len(listings) == 1
    listing = listings[0]
    assert listing.external_id == "v1|1234|0"
    assert listing.price.amount == Decimal("45.00")
    assert listing.shipping is not None and listing.shipping.amount == Decimal("1.55")
    assert listing.buying_format is BuyingFormat.FIXED_PRICE
    assert listing.url == "https://www.ebay.co.uk/itm/1234"
    assert listing.item_location_country == "GB"


@respx.mock
def test_category_sweep_with_auction_end_window() -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "TKN", "expires_in": 7200})
    )
    auction_item = {
        **_ITEM,
        "buyingOptions": ["AUCTION"],
        "itemEndDate": "2030-01-01T00:00:00.000Z",
    }
    route = respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [auction_item]})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)

    listings = src.fetch(
        category_ids=["183454"],
        buying_options=("AUCTION",),
        item_end_within_hours=3,
        sort="endingSoonest",
    )

    req = route.calls.last.request
    assert "q" not in req.url.params  # category-only sweep, no keyword
    assert req.url.params["category_ids"] == "183454"
    assert req.url.params["sort"] == "endingSoonest"
    flt = req.url.params["filter"]
    assert "buyingOptions:{AUCTION}" in flt
    assert "itemEndDate:[" in flt

    assert listings[0].buying_format is BuyingFormat.AUCTION
    assert listings[0].item_end_date == "2030-01-01T00:00:00.000Z"


@respx.mock
def test_auction_bid_and_offer_fields() -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "TKN", "expires_in": 7200})
    )
    item = {
        **_ITEM,
        "buyingOptions": ["AUCTION", "BEST_OFFER"],
        "bidCount": 2,
        "currentBidPrice": {"value": "12.50", "currency": "GBP"},
    }
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": [item]})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    listing = src.fetch(query="x")[0]
    assert listing.bid_count == 2
    assert listing.current_bid_price is not None
    assert listing.current_bid_price.amount == Decimal("12.50")
    assert listing.accepts_best_offer is True


@respx.mock
def test_token_is_cached_across_calls() -> None:
    token_route = respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "TKN", "expires_in": 7200})
    )
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": []})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)
    src.fetch(query="a")
    src.fetch(query="b")
    assert token_route.call_count == 1  # token minted once, then cached
