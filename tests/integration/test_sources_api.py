from __future__ import annotations

import warnings
from pathlib import Path

import httpx
import respx
from fastapi.testclient import TestClient

from trader.config import get_settings
from trader.main import app
from trader.providers.factory import configure_app_providers
from trader.services.credentials import CredentialStore
from trader.services.sources import DEFAULT_ENABLED

warnings.filterwarnings("ignore")


def _client(tmp_path: Path) -> TestClient:
    # Hermetic credential store so the test never touches the real .trader file.
    app.state.credentials = CredentialStore.create(
        get_settings(), set(DEFAULT_ENABLED), path=tmp_path / "creds.json"
    )
    configure_app_providers(app)
    return TestClient(app)


def test_lists_uk_sources(tmp_path: Path) -> None:
    data = _client(tmp_path).get("/sources").json()
    ids = {s["id"] for s in data["sources"]}
    assert {"ebay_uk_sold", "ebay_uk_active", "cardmarket", "pricecharting"} <= ids

    sold = next(s for s in data["sources"] if s["id"] == "ebay_uk_sold")
    assert sold["available"] and sold["enabled"] and not sold["configured"]
    assert sold["signup_url"].startswith("https://")


def test_set_credentials_masks_and_activates(tmp_path: Path) -> None:
    resp = _client(tmp_path).put("/sources/credentials", json={"rapidapi_key": "abcd1234EFGH"})
    body = resp.json()
    assert body["credentials"]["rapidapi_key"] == "••••EFGH"
    sold = next(s for s in body["sources"] if s["id"] == "ebay_uk_sold")
    assert sold["configured"] and sold["active"]


def test_cannot_enable_unavailable_source(tmp_path: Path) -> None:
    resp = _client(tmp_path).put("/sources/pricecharting", json={"enabled": True})
    assert resp.status_code == 400


@respx.mock
def test_test_ebay_flags_category_sweep_rejection(tmp_path: Path) -> None:
    # Keys that pass a keyword search but fail the category 'scour' (the real scan call)
    # must report ok:False with eBay's own error — not a false "ready to scan".
    client = _client(tmp_path)
    app.state.credentials.set_many(
        {"ebay_client_id": "App-PRD-1234", "ebay_client_secret": "PRD-secret"}
    )
    configure_app_providers(app)

    respx.post("https://api.ebay.com/identity/v1/oauth2/token").mock(
        return_value=httpx.Response(200, json={"access_token": "T", "expires_in": 7200})
    )
    respx.get("https://api.ebay.com/buy/browse/v1/item_summary/search").mock(
        side_effect=[
            httpx.Response(200, json={"itemSummaries": []}),  # keyword search OK
            httpx.Response(  # category sweep rejected by eBay
                403,
                json={"errors": [{"errorId": 1100, "message": "Insufficient permissions."}]},
            ),
        ]
    )

    body = client.post("/sources/test/ebay").json()
    assert body["ok"] is False
    assert "scour" in body["detail"].lower()
    assert "errorId 1100" in body["detail"]
