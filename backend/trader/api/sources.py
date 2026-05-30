"""Price-source + credential management for the UI.

`GET /sources` lists every known UK price source with its status and a signup
link; `PUT /sources/credentials` accepts API keys (entered in the UI) and applies
them immediately; `PUT /sources/{id}` toggles a source on/off.
"""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..providers.ebay_errors import ebay_error_detail
from ..providers.factory import build_browse_source, configure_app_providers
from ..services.credentials import SECRET_FIELDS, CredentialStore
from ..services.sources import SOURCES, SOURCES_BY_ID, SourceInfo
from ..services.watchlist import POKEMON_SINGLES_GB

router = APIRouter(prefix="/sources", tags=["sources"])

_LOCAL_NOTE = (
    "Keys are stored locally in .trader/credentials.json (gitignored, plaintext). "
    "Only enter them on a machine you control."
)


def _source_state(store: CredentialStore, s: SourceInfo) -> dict[str, Any]:
    configured = store.is_configured(*s.requires) if s.requires else True
    enabled = store.is_enabled(s.id) if s.available else False
    return {
        "id": s.id,
        "name": s.name,
        "role": s.role,
        "region": s.region,
        "currency": s.currency,
        "requires": list(s.requires),
        "signup_url": s.signup_url,
        "accuracy": s.accuracy,
        "available": s.available,
        "configured": configured,
        "enabled": enabled,
        "active": s.available and enabled and configured,
    }


def _payload(store: CredentialStore) -> dict[str, Any]:
    return {
        "sources": [_source_state(store, s) for s in SOURCES],
        "credentials": store.masked(),
        "note": _LOCAL_NOTE,
    }


class CredentialsIn(BaseModel):
    ebay_client_id: str | None = None
    ebay_client_secret: str | None = None
    rapidapi_key: str | None = None
    pricecharting_api_key: str | None = None
    anthropic_api_key: str | None = None
    ebay_user_token: str | None = None
    telegram_bot_token: str | None = None
    telegram_chat_id: str | None = None


class EnableIn(BaseModel):
    enabled: bool


@router.get("")
def list_sources(request: Request) -> dict[str, Any]:
    return _payload(request.app.state.credentials)


@router.put("/credentials")
def update_credentials(request: Request, body: CredentialsIn) -> dict[str, Any]:
    store: CredentialStore = request.app.state.credentials
    store.set_many({k: v for k, v in body.model_dump().items() if v is not None})
    configure_app_providers(request.app)
    return _payload(store)


@router.delete("/credentials/{key}")
def clear_credential(request: Request, key: str) -> dict[str, Any]:
    store: CredentialStore = request.app.state.credentials
    if key not in SECRET_FIELDS:
        raise HTTPException(status_code=404, detail="unknown credential")
    store.clear(key)
    configure_app_providers(request.app)
    return _payload(store)


@router.post("/test/ebay")
def test_ebay(request: Request) -> dict[str, Any]:
    """Check the eBay keys the way a live scan actually uses them.

    A keyword search alone can pass on a keyset that still can't run the marketplace
    "scour" — so we test both a keyword search *and* a category sweep (what the scan
    does). That stops the button saying "ready to scan" when the scan will 403.
    """
    store: CredentialStore = request.app.state.credentials
    client_id = store.get("ebay_client_id") or ""
    if not store.is_configured("ebay_client_id", "ebay_client_secret"):
        return {"ok": False, "detail": "Enter both your eBay App ID and Cert ID first."}
    source = build_browse_source(store, request.app.state.settings)
    if source is None:
        return {"ok": False, "detail": "Enable the 'eBay UK — Active listings' source first."}

    # 1) Keyword search — the minimum a working keyset can do.
    try:
        source.fetch(query="charizard", limit=1)
    except httpx.HTTPStatusError as exc:
        return {"ok": False, "detail": _key_reject_detail(exc, client_id)}
    except httpx.HTTPError as exc:
        return {"ok": False, "detail": f"Couldn't reach eBay: {exc}"}

    # 2) Category sweep — exactly what "Run live scan" does. This is where a keyset that
    #    lacks Buy/Browse production access fails, even though step 1 passed.
    try:
        source.fetch(
            category_ids=[POKEMON_SINGLES_GB],
            buying_options=("FIXED_PRICE", "BEST_OFFER"),
            sort="price",
            limit=1,
        )
    except httpx.HTTPStatusError as exc:
        real = ebay_error_detail(exc) or f"HTTP {exc.response.status_code}"
        return {
            "ok": False,
            "detail": (
                f"Keyword search works, but the category 'scour eBay' scan was rejected: {real}. "
                "This is a keyset permission, not a wrong key — your eBay app likely needs "
                "Buy/Browse API production access. 'Check a card' still works meanwhile."
            ),
        }
    except httpx.HTTPError as exc:
        return {"ok": False, "detail": f"Couldn't reach eBay for the category scan: {exc}"}

    return {"ok": True, "detail": "eBay keys work — keyword and category scans both pass. 🎉"}


def _key_reject_detail(exc: httpx.HTTPStatusError, client_id: str) -> str:
    """Why eBay rejected the keyword search — eBay's own words, plus a sandbox hint."""
    if exc.response.status_code in (401, 403):
        if "SBX" in client_id.upper():
            return (
                "These are SANDBOX keys (App ID has 'SBX'). Paste your PRODUCTION App ID + "
                "Cert ID (they contain 'PRD')."
            )
        real = ebay_error_detail(exc)
        return f"eBay rejected these keys (401/403). {real}".strip()
    real = ebay_error_detail(exc)
    return f"eBay error {exc.response.status_code}. {real}".strip()


@router.put("/{source_id}")
def set_source_enabled(request: Request, source_id: str, body: EnableIn) -> dict[str, Any]:
    store: CredentialStore = request.app.state.credentials
    source = SOURCES_BY_ID.get(source_id)
    if source is None:
        raise HTTPException(status_code=404, detail="unknown source")
    if body.enabled and not source.available:
        raise HTTPException(
            status_code=400,
            detail=f"{source.name} is not available: {source.accuracy}",
        )
    store.set_enabled(source_id, body.enabled)
    configure_app_providers(request.app)
    return _source_state(store, source)
