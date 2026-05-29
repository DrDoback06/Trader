from __future__ import annotations

import json
import warnings

import httpx
import respx
from fastapi.testclient import TestClient

from trader.core.money import Money
from trader.main import app
from trader.providers.ebay_sell import EbaySellClient, SellConfig
from trader.services.relist import build_listing_draft

warnings.filterwarnings("ignore")
BASE = "https://api.ebay.com/sell/inventory/v1"


def test_build_draft_raw_card() -> None:
    draft = build_listing_draft(
        sku="TRDR-1", card_name="Charizard ex", number="199/165", set_name="151",
        condition="RAW_NM", price=Money.gbp(80), category_id="183454",
    )
    assert draft.condition == "USED_EXCELLENT"
    assert "Charizard ex" in draft.title and "199/165" in draft.title
    assert draft.price.amount == 80


def test_build_draft_graded() -> None:
    draft = build_listing_draft(
        sku="TRDR-2", card_name="Charizard ex", number="199/165", set_name="151",
        grade="PSA 9", condition="GRADED", price=Money.gbp(120), category_id="183454",
    )
    assert "PSA 9" in draft.title
    assert draft.condition == "LIKE_NEW"
    assert draft.grade == "PSA 9"


def test_title_truncated_to_80() -> None:
    draft = build_listing_draft(
        sku="s", card_name="X" * 90, price=Money.gbp(5), category_id="1"
    )
    assert len(draft.title) <= 80


@respx.mock
def test_relist_runs_inventory_offer_publish() -> None:
    inv = respx.put(f"{BASE}/inventory_item/TRDR-1").mock(return_value=httpx.Response(204))
    offer = respx.post(f"{BASE}/offer").mock(
        return_value=httpx.Response(201, json={"offerId": "OFFER1"})
    )
    pub = respx.post(f"{BASE}/offer/OFFER1/publish").mock(
        return_value=httpx.Response(200, json={"listingId": "LIST1"})
    )
    cfg = SellConfig(
        fulfillment_policy_id="f", payment_policy_id="p", return_policy_id="r",
        merchant_location_key="loc",
    )
    client = EbaySellClient("USERTOKEN", BASE, cfg)
    draft = build_listing_draft(
        sku="TRDR-1", card_name="Charizard ex", number="199/165", set_name="151",
        price=Money.gbp(80), category_id="183454",
    )
    result = client.relist(draft, ["https://mine/photo.jpg"])

    assert result.offer_id == "OFFER1" and result.listing_id == "LIST1"
    assert inv.called and offer.called and pub.called
    assert inv.calls.last.request.headers["Authorization"] == "Bearer USERTOKEN"
    inv_body = json.loads(inv.calls.last.request.content)
    assert inv_body["product"]["imageUrls"] == ["https://mine/photo.jpg"]
    offer_body = json.loads(offer.calls.last.request.content)
    assert offer_body["marketplaceId"] == "EBAY_GB"
    assert offer_body["listingPolicies"]["fulfillmentPolicyId"] == "f"
    assert offer_body["merchantLocationKey"] == "loc"


def test_relist_endpoint_previews_then_requires_config() -> None:
    client = TestClient(app)
    client.post("/portfolio/buy", json={"deal_id": "1001"})
    pid = client.get("/portfolio").json()["positions"][0]["id"]

    preview = client.post(f"/portfolio/{pid}/relist", json={"publish": False}).json()
    assert "Charizard" in preview["preview"]["title"]
    assert "photos" in preview["note"].lower()

    # Publishing without seller config is refused, not silently attempted.
    resp = client.post(f"/portfolio/{pid}/relist", json={"publish": True, "image_urls": ["http://x"]})
    assert resp.status_code == 400
