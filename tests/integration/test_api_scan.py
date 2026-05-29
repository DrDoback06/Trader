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


def test_watchlist_and_quota_endpoints() -> None:
    client = TestClient(app)
    watchlist = client.get("/watchlist").json()
    assert len(watchlist) >= 1
    assert "query" in watchlist[0]

    quota = client.get("/quota").json()
    assert quota["daily_budget"] >= 1
    assert quota["remaining"] <= quota["daily_budget"]
