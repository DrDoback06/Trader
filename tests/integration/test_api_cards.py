from __future__ import annotations

import warnings
from pathlib import Path

import httpx
import respx
from fastapi.testclient import TestClient

from trader.config import get_settings
from trader.main import app
from trader.providers.factory import configure_app_providers
from trader.services.cardlist import CardList
from trader.services.credentials import CredentialStore
from trader.services.sources import DEFAULT_ENABLED

warnings.filterwarnings("ignore")


def _fresh_cardlist(tmp_path: Path, seed: list[str]) -> CardList:
    return CardList.create(tmp_path / "cardlist.json", seed=seed)


def test_card_list_crud(tmp_path: Path) -> None:
    original = app.state.cardlist
    app.state.cardlist = _fresh_cardlist(tmp_path, ["Charizard ex 199/165"])
    try:
        client = TestClient(app)
        assert client.get("/cards").json()["cards"] == ["Charizard ex 199/165"]

        added = client.post("/cards", json={"query": "Pikachu 173/165"}).json()
        assert added["cards"] == ["Charizard ex 199/165", "Pikachu 173/165"]

        # Duplicate is rejected with a 400.
        assert client.post("/cards", json={"query": "charizard ex 199/165"}).status_code == 400

        removed = client.request("DELETE", "/cards", params={"query": "Charizard ex 199/165"})
        assert removed.json()["cards"] == ["Pikachu 173/165"]
    finally:
        app.state.cardlist = original


def test_scan_cards_requires_credentials(tmp_path: Path) -> None:
    original = app.state.cardlist
    app.state.cardlist = _fresh_cardlist(tmp_path, ["Charizard ex 199/165"])
    try:
        resp = TestClient(app).post("/scan/cards")
        assert resp.status_code == 400
        assert "Active listings" in resp.json()["detail"]
    finally:
        app.state.cardlist = original


@respx.mock
def test_scan_cards_searches_each_saved_card(tmp_path: Path) -> None:
    original_creds = app.state.credentials
    original_cards = app.state.cardlist
    app.state.settings.access_password = ""
    app.state.credentials = CredentialStore.create(
        get_settings(), set(DEFAULT_ENABLED), path=tmp_path / "creds.json"
    )
    app.state.credentials.set_many({"ebay_client_id": "App-PRD-1", "ebay_client_secret": "sec"})
    app.state.cardlist = _fresh_cardlist(tmp_path, ["Charizard ex 199/165", "Pikachu 173/165"])
    configure_app_providers(app)
    try:
        respx.post("https://api.ebay.com/identity/v1/oauth2/token").mock(
            return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
        )
        item = {
            "itemId": "v1|1|0",
            "title": "Pokemon 151 Charizard ex 199/165",
            "price": {"value": "40.00", "currency": "GBP"},
            "buyingOptions": ["FIXED_PRICE"],
            "itemLocation": {"country": "GB"},
            "itemWebUrl": "https://www.ebay.co.uk/itm/1",
        }
        route = respx.get("https://api.ebay.com/buy/browse/v1/item_summary/search").mock(
            return_value=httpx.Response(200, json={"itemSummaries": [item]})
        )
        # Free market price so the batch produces valued deals (no RapidAPI needed).
        respx.get("https://api.pokemontcg.io/v2/cards").mock(
            return_value=httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "name": "Charizard ex",
                            "number": "199",
                            "cardmarket": {"prices": {"trendPrice": 90.0}},
                        }
                    ]
                },
            )
        )

        r = TestClient(app).post("/scan/cards", json={"max_valuations": 10}).json()
        assert r["mode"] == "cards:2"
        assert r["targets_scanned"] == 2  # both saved cards searched
        # One eBay search request per saved card (each is a keyword search).
        searched = [c.request.url.params.get("q") for c in route.calls]
        assert "Charizard ex 199/165" in searched
        assert "Pikachu 173/165" in searched
    finally:
        app.state.credentials = original_creds
        app.state.cardlist = original_cards
        configure_app_providers(app)
