from __future__ import annotations

from typing import Any

import httpx
import respx
from fastapi.testclient import TestClient

from trader.main import app
from trader.providers.ebay_browse import EbayBrowseSource
from trader.providers.ebay_oauth import EbayOAuth
from trader.services.pipeline import PipelineConfig, resolve_searched_card
from trader.services.quota import DailyQuota
from trader.services.scanner import search_card

OAUTH = "https://api.ebay.com/identity/v1/oauth2/token"
BROWSE = "https://api.ebay.com/buy/browse/v1"


def _item(item_id: str, title: str, value: str = "45.00") -> dict[str, Any]:
    return {
        "itemId": item_id,
        "title": title,
        "price": {"value": value, "currency": "GBP"},
        "buyingOptions": ["FIXED_PRICE"],
        "condition": "Used",
        "itemWebUrl": f"https://www.ebay.co.uk/itm/{item_id}",
    }


@respx.mock
def test_search_values_against_card_and_drops_wrong_variant(
    catalogue: Any, sold_provider: Any
) -> None:
    respx.post(OAUTH).mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    items = [
        _item("A", "Pokemon 151 Charizard ex 199/165 Near Mint"),
        _item("B", "Charizard ex 199/165 ULTRA RARE NM L@@K", value="38.00"),
        _item("C", "Charizard ex 12/165 Near Mint"),  # wrong number -> dropped
        _item("D", "Charizard ex 151 Near Mint"),  # no number -> kept (name match)
    ]
    respx.get(f"{BROWSE}/item_summary/search").mock(
        return_value=httpx.Response(200, json={"itemSummaries": items})
    )
    src = EbayBrowseSource(EbayOAuth("id", "sec", OAUTH), BROWSE)

    cfg = PipelineConfig()
    card = resolve_searched_card("Charizard ex 199/165", catalogue, cfg)
    result = search_card(
        "Charizard ex 199/165",
        card,
        src,
        sold_provider,
        quota=DailyQuota(10),
        cfg=cfg,
        category_ids=("183454",),
    )

    kept = {d.listing.external_id for d in result.deals}
    assert kept == {"A", "B", "D"}  # the wrong-number variant C is dropped
    # Every kept listing is valued against the searched card (fixture RAW_NM median 80).
    assert result.valued == 3
    assert all(d.valuation is not None for d in result.deals)
    assert all(float(d.valuation.median.amount) == 80.0 for d in result.deals)


def test_search_requires_credentials() -> None:
    app.state.settings.access_password = ""
    client = TestClient(app)
    resp = client.post("/search", json={"query": "Charizard ex 199/165"})
    assert resp.status_code == 400
    assert "isn't ready" in resp.json()["detail"]


def test_search_rejects_short_query() -> None:
    app.state.settings.access_password = ""
    client = TestClient(app)
    resp = client.post("/search", json={"query": "ab"})
    assert resp.status_code == 400
    assert "card name" in resp.json()["detail"]
