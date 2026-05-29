from __future__ import annotations

import warnings

from fastapi.testclient import TestClient

from trader.main import app

warnings.filterwarnings("ignore")


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
