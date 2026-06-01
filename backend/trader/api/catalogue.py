"""Catalogue browser: list every set, and the cards within a set (ordered).

Reads the in-memory catalogue, so it works on the bundled seed sets immediately
and on the full ~20k-card import once that's run. Set/card images appear when the
catalogue was imported with images (see tools/import_pokemontcg).
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request

router = APIRouter(prefix="/catalogue", tags=["catalogue"])


@router.get("/sets")
def list_sets(request: Request) -> dict[str, Any]:
    cat = request.app.state.catalogue
    return {"total_cards": len(cat), "sets": cat.sets()}


# Sealed product isn't single cards, so it isn't in the card catalogue — offer a set of
# ready-made searches the user can run (or value) like any card query.
_SEALED_PRESETS: list[dict[str, str]] = [
    {"label": "Booster box", "query": "pokemon booster box"},
    {"label": "Elite Trainer Box (ETB)", "query": "pokemon elite trainer box"},
    {"label": "Booster bundle", "query": "pokemon booster bundle"},
    {"label": "151 booster box", "query": "pokemon 151 booster box"},
    {"label": "151 ETB", "query": "pokemon 151 elite trainer box"},
    {
        "label": "Prismatic Evolutions ETB",
        "query": "pokemon prismatic evolutions elite trainer box",
    },
    {"label": "Surging Sparks booster box", "query": "pokemon surging sparks booster box"},
    {"label": "Booster bundle (single packs)", "query": "pokemon booster pack"},
]


@router.get("/sealed")
def list_sealed(request: Request) -> dict[str, Any]:
    """Ready-made sealed-product searches (boxes / ETBs / bundles) to run from Browse."""
    return {"sealed": _SEALED_PRESETS}


@router.get("/sets/{set_code}/cards")
def set_cards(request: Request, set_code: str) -> dict[str, Any]:
    cat = request.app.state.catalogue
    cards = cat.cards_in_set(set_code)
    if not cards:
        raise HTTPException(status_code=404, detail="unknown or empty set")
    insights = getattr(request.app.state, "card_insights", {}) or {}
    out = []
    for c in cards:
        info = insights.get(c.id) or {}
        out.append({
            "id": c.id,
            "name": c.name,
            "number": c.number,
            "rarity": c.rarity,
            "finish": c.finish,
            "image_url": c.image_url,
            "market_value": info.get("market_value"),
            "gem_score": info.get("gem_score"),
            "active_listings_count": info.get("active_listings_count"),
            "trend_pct": info.get("trend_pct"),
            "attention_delta_7d": info.get("attention_delta_7d"),
        })
    return {
        "set_code": set_code,
        "set_name": cards[0].set_name,
        "cards": out,
    }
