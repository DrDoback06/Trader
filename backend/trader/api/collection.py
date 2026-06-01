"""Collection endpoints: track what you own + where you're selling it.

A local 'collection' keyed by catalogue card id, separate from the Portfolio. Lets the
Browse page show owned count / condition / paid / target price / for-sale / notes per
card, plus the eBay listings you're selling it through (added manually, or best-effort
auto-pulled from your eBay seller account).

Card ids contain '/' (e.g. ``POKEMON-MEW-199/165``), which can't go in a URL *path*
segment cleanly (``%2F`` gets rejected/mis-routed), so the card id travels in the JSON
body or a query param instead.
"""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..providers.factory import build_sell_client
from ..services.collection import Listing
from ..services.pipeline import resolve_searched_card

router = APIRouter(prefix="/collection", tags=["collection"])


def _entry_dict(card_id: str, request: Request) -> dict[str, Any]:
    return {"card_id": card_id, **request.app.state.collection.get(card_id).to_dict()}


@router.get("")
def get_collection(request: Request) -> dict[str, Any]:
    """Every non-empty collection entry, keyed by card id (for Browse to overlay)."""
    return {
        "cards": {
            cid: entry.to_dict() for cid, entry in request.app.state.collection.all().items()
        }
    }


class EntryPatch(BaseModel):
    card_id: str
    owned: int | None = None
    condition: str | None = None
    paid: float | None = None
    target_price: float | None = None
    for_sale: bool | None = None
    notes: str | None = None


@router.put("/card")
def update_card(request: Request, body: EntryPatch) -> dict[str, Any]:
    patch = body.model_dump(exclude_unset=True, exclude={"card_id"})
    request.app.state.collection.update(body.card_id, patch)
    return _entry_dict(body.card_id, request)


class ListingIn(BaseModel):
    card_id: str
    url: str
    item_id: str | None = None
    price: float | None = None


@router.post("/listings")
def add_listing(request: Request, body: ListingIn) -> dict[str, Any]:
    url = body.url.strip()
    if not url.startswith("http"):
        raise HTTPException(status_code=400, detail="Enter a full listing URL (https://…).")
    request.app.state.collection.add_listing(
        body.card_id, Listing(url=url, item_id=body.item_id, price=body.price, source="manual")
    )
    return _entry_dict(body.card_id, request)


@router.delete("/listings")
def remove_listing(request: Request, card_id: str, ref: str) -> dict[str, Any]:
    request.app.state.collection.remove_listing(card_id, ref)
    return _entry_dict(card_id, request)


@router.post("/import/ebay")
def import_ebay_listings(request: Request) -> dict[str, Any]:
    """Best-effort: pull the seller's own active eBay listings and attach each to the
    catalogue card its title resolves to. Needs the eBay Sell source enabled + a user
    token. Listings created in eBay's web UI may not be returned by the Sell API — those
    can still be added as manual links."""
    sell = build_sell_client(request.app.state.credentials, request.app.state.settings)
    if sell is None:
        raise HTTPException(
            status_code=400,
            detail="Connect eBay selling first: enable 'eBay relist (Sell API)' and add your "
            "eBay user token under Sources & Keys.",
        )
    try:
        listings = sell.my_active_listings()
    except httpx.HTTPStatusError as exc:
        detail = f"eBay rejected the request (HTTP {exc.response.status_code})."
        if exc.response.status_code in (401, 403):
            detail = (
                "Your eBay user token was rejected (401/403). It needs the sell.inventory "
                "scope and may have expired — re-add it under Sources & Keys."
            )
        raise HTTPException(status_code=502, detail=detail) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Couldn't reach eBay: {exc}") from exc

    catalogue = request.app.state.catalogue
    cfg = request.app.state.pipeline_cfg
    matched = 0
    unmatched: list[str] = []
    for item in listings:
        title = item.get("title") or ""
        url = item.get("url")
        if not title or not url:
            continue
        card = resolve_searched_card(title, catalogue, cfg)
        if card.id.startswith("SEARCH:"):  # couldn't pin it to a real catalogue card
            unmatched.append(title)
            continue
        request.app.state.collection.add_listing(
            card.id,
            Listing(url=url, item_id=item.get("item_id"), price=item.get("price"), source="ebay"),
        )
        matched += 1

    return {
        "found": len(listings),
        "matched": matched,
        "unmatched": unmatched[:20],
        "note": (
            "Listings created in eBay's web UI aren't always returned by the Sell API. "
            "Add any missing ones as manual links."
            if len(listings) == 0
            else ""
        ),
    }
