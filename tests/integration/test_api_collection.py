from __future__ import annotations

import warnings
from pathlib import Path

import httpx
import respx
from fastapi.testclient import TestClient

from trader.config import get_settings
from trader.main import app
from trader.providers.factory import configure_app_providers
from trader.services.collection import Collection
from trader.services.credentials import CredentialStore
from trader.services.sources import DEFAULT_ENABLED

warnings.filterwarnings("ignore")


def _fresh(tmp_path: Path) -> Collection:
    return Collection.create(tmp_path / "collection.json")


def test_collection_crud_and_listings(tmp_path: Path) -> None:
    original = app.state.collection
    app.state.collection = _fresh(tmp_path)
    try:
        client = TestClient(app)
        assert client.get("/collection").json()["cards"] == {}

        # A real card id contains '/', which must round-trip in the body (not the path).
        card_id = "POKEMON-MEW-199/165"
        body = client.put(
            "/collection/card",
            json={"card_id": card_id, "owned": 3, "condition": "NM", "for_sale": True},
        ).json()
        assert body["card_id"] == card_id
        assert body["owned"] == 3 and body["for_sale"] is True

        # Manual listing link.
        body = client.post(
            "/collection/listings",
            json={"card_id": card_id, "url": "https://www.ebay.co.uk/itm/123"},
        ).json()
        assert len(body["listings"]) == 1

        # A bad (non-http) link is rejected.
        bad = client.post(
            "/collection/listings", json={"card_id": card_id, "url": "nope"}
        )
        assert bad.status_code == 400

        # Shows up in the whole-collection overlay, under the slash-containing id.
        all_cards = client.get("/collection").json()["cards"]
        assert card_id in all_cards
    finally:
        app.state.collection = original


def test_sealed_presets_listed() -> None:
    data = TestClient(app).get("/catalogue/sealed").json()
    labels = {s["label"] for s in data["sealed"]}
    assert "Booster box" in labels
    assert all(s["query"] for s in data["sealed"])


def test_import_ebay_requires_sell_source(tmp_path: Path) -> None:
    original = app.state.credentials
    app.state.credentials = CredentialStore.create(
        get_settings(), set(DEFAULT_ENABLED), path=tmp_path / "creds.json"
    )
    configure_app_providers(app)
    try:
        resp = TestClient(app).post("/collection/import/ebay")
        assert resp.status_code == 400
        assert "Sell API" in resp.json()["detail"]
    finally:
        app.state.credentials = original
        configure_app_providers(app)


@respx.mock
def test_import_ebay_matches_listings_to_cards(tmp_path: Path) -> None:
    original_creds = app.state.credentials
    original_col = app.state.collection
    app.state.settings.access_password = ""
    app.state.credentials = CredentialStore.create(
        get_settings(), set(DEFAULT_ENABLED) | {"relist"}, path=tmp_path / "creds.json"
    )
    app.state.credentials.set_many({"ebay_user_token": "USER-TOKEN"})
    app.state.collection = _fresh(tmp_path)
    configure_app_providers(app)
    try:
        respx.get("https://api.ebay.com/sell/inventory/v1/offer").mock(
            return_value=httpx.Response(
                200,
                json={
                    "offers": [
                        {
                            "sku": "char-199",
                            "listingDescription": "Charizard ex 199/165 151",
                            "listing": {"listingId": "2255"},
                            "pricingSummary": {"price": {"value": "85.00", "currency": "GBP"}},
                        }
                    ]
                },
            )
        )
        r = TestClient(app).post("/collection/import/ebay").json()
        assert r["found"] == 1
        assert r["matched"] == 1
        # The listing was attached to the resolved catalogue card.
        cards = app.state.collection.all()
        assert any(entry.listings for entry in cards.values())
    finally:
        app.state.credentials = original_creds
        app.state.collection = original_col
        configure_app_providers(app)
