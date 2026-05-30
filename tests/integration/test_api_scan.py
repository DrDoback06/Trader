from __future__ import annotations

import warnings
from types import SimpleNamespace

from fastapi.testclient import TestClient

from trader.api.scan import ScanRequest, _targets_for
from trader.main import app

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
