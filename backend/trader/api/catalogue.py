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


@router.get("/sets/{set_code}/cards")
def set_cards(request: Request, set_code: str) -> dict[str, Any]:
    cat = request.app.state.catalogue
    cards = cat.cards_in_set(set_code)
    if not cards:
        raise HTTPException(status_code=404, detail="unknown or empty set")
    return {
        "set_code": set_code,
        "set_name": cards[0].set_name,
        "cards": [
            {
                "id": c.id,
                "name": c.name,
                "number": c.number,
                "rarity": c.rarity,
                "finish": c.finish,
                "image_url": c.image_url,
            }
            for c in cards
        ],
    }
