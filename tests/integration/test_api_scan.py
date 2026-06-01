from __future__ import annotations

import warnings
from pathlib import Path
from types import SimpleNamespace

import httpx
import respx
from fastapi.testclient import TestClient

from trader.api.scan import ScanRequest, _card_targets, _targets_for
from trader.config import get_settings
from trader.main import app
from trader.providers.factory import configure_app_providers
from trader.services.credentials import CredentialStore
from trader.services.sources import DEFAULT_ENABLED

warnings.filterwarnings("ignore")


def test_everything_uses_keyword_targets_on_basic_keyset() -> None:
    # A standard eBay keyset can't run whole-category sweeps, so "everything" fans out
    # across keyword searches with the category filter stripped (proven to work).
    app.state.settings.ebay_buy_api_full_access = False
    targets = _targets_for(SimpleNamespace(app=app), ScanRequest(mode="everything"))
    assert targets
    assert all(t.query for t in targets)  # every target is a keyword search
    assert all(not t.category_ids for t in targets)  # no category filter on a basic keyset


def test_everything_uses_category_sweeps_with_full_access() -> None:
    app.state.settings.ebay_buy_api_full_access = True
    try:
        targets = _targets_for(SimpleNamespace(app=app), ScanRequest(mode="everything"))
        # With full access the category-only sweeps (no query) are included.
        assert any(not t.query and t.category_ids for t in targets)
    finally:
        app.state.settings.ebay_buy_api_full_access = False


def test_card_targets_are_keyword_only_with_variants() -> None:
    targets = _card_targets(
        "Charizard ex 199/165", graded=True, include_misspellings=True, max_price=50
    )
    queries = [t.query for t in targets]
    assert "Charizard ex 199/165" in queries  # the exact card
    assert any(q.endswith("PSA") for q in queries)  # graded variant
    assert any("199/165" not in q and q != "Charizard ex 199/165" for q in queries)  # a typo
    assert all(not t.category_ids for t in targets)  # keyword-only — works on a basic keyset


@respx.mock
def test_scan_card_searches_specific_card_by_keyword(tmp_path: Path) -> None:
    original = app.state.credentials  # restore after — this test mutates shared app state
    app.state.settings.access_password = ""
    app.state.credentials = CredentialStore.create(
        get_settings(), set(DEFAULT_ENABLED), path=tmp_path / "creds.json"
    )
    app.state.credentials.set_many({"ebay_client_id": "App-PRD-1", "ebay_client_secret": "sec"})
    configure_app_providers(app)
    try:
        item = {
            "itemId": "v1|1|0",
            "title": "Pokemon 151 Charizard ex 199/165 Near Mint",
            "price": {"value": "40.00", "currency": "GBP"},
            "buyingOptions": ["FIXED_PRICE"],
            "itemLocation": {"country": "GB"},
            "itemWebUrl": "https://www.ebay.co.uk/itm/1",
        }
        respx.post("https://api.ebay.com/identity/v1/oauth2/token").mock(
            return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
        )
        route = respx.get("https://api.ebay.com/buy/browse/v1/item_summary/search").mock(
            return_value=httpx.Response(200, json={"itemSummaries": [item]})
        )
        # The free pokemontcg.io market-price source is on by default — value the listing
        # against a £90 Cardmarket reference so the deal gets an ROI (a £40 buy on a £90
        # card is a clear steal), proving the no-key valuation path end-to-end.
        respx.get("https://api.pokemontcg.io/v2/cards").mock(
            return_value=httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "id": "mew-199",
                            "name": "Charizard ex",
                            "number": "199",
                            "cardmarket": {"prices": {"trendPrice": 105.0, "lowPrice": 80.0}},
                        }
                    ]
                },
            )
        )

        r = TestClient(app).post("/scan/card", json={"query": "Charizard ex 199/165"}).json()
        assert r["mode"] == "card:Charizard ex 199/165"
        assert r["listings_seen"] >= 1
        assert r["valued"] >= 1  # the free market-price source produced a valuation
        deal = r["deals"][0]
        assert deal["valuation"]["provider"] == "pokemontcg_market"
        assert deal["economics"] is not None and deal["economics"]["roi"] > 0
        # A keyword query with NO category browsing (works on a standard keyset).
        req = route.calls.last.request
        assert req.url.params["q"] == "Charizard ex 199/165"
        assert "category_ids" not in req.url.params
    finally:
        app.state.credentials = original
        configure_app_providers(app)


def test_scan_requires_credentials() -> None:
    client = TestClient(app)
    resp = client.post("/scan")
    assert resp.status_code == 400
    assert "Active listings" in resp.json()["detail"]


def test_scan_accepts_discovery_mode_body() -> None:
    client = TestClient(app)
    resp = client.post("/scan", json={"mode": "ending_soon", "ending_within_hours": 3})
    assert resp.status_code == 400  # still needs creds, but the body parsed fine
    assert "Active listings" in resp.json()["detail"]


def test_watchlist_and_quota_endpoints() -> None:
    client = TestClient(app)
    watchlist = client.get("/watchlist").json()
    assert len(watchlist) >= 1
    assert "query" in watchlist[0]

    quota = client.get("/quota").json()
    assert quota["daily_budget"] >= 1
    assert quota["remaining"] <= quota["daily_budget"]


def test_evaluate_prices_a_user_supplied_card() -> None:
    # "Check a card" works without eBay listing keys (only needs the sold-price source).
    app.state.settings.access_password = ""
    client = TestClient(app)
    resp = client.post("/evaluate", json={"query": "Charizard ex 199/165", "ask_price": 45})
    assert resp.status_code == 200
    body = resp.json()
    # Echoes the listing we asked about and always returns a structured verdict, even
    # offline (valuation/economics may be None without a live sold-price key configured).
    assert body["listing"]["title"] == "Charizard ex 199/165"
    assert body["listing"]["price"]["amount"] == 45.0
    assert "passed_rules" in body
    assert "rule_reasons" in body


def test_evaluate_rejects_bad_input() -> None:
    client = TestClient(app)
    assert client.post("/evaluate", json={"query": "ab", "ask_price": 5}).status_code == 400
    assert (
        client.post("/evaluate", json={"query": "Charizard ex", "ask_price": 0}).status_code == 400
    )
