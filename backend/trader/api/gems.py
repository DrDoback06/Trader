"""Hidden-gem ranking endpoint.

Reads the persistent in-process cache of recent valuations and active-listing
counts (collected by every scan) and returns cards ranked by ``compute_gem_score``.
Different from ``GET /deals`` because it returns *cards* with cached evidence,
not the live listings that triggered a scan — so it works between scans, lets
the user explore the catalogue, and feeds the Browse-tile 💎 badges.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from fastapi import APIRouter, Request

from ..core.money import Money
from ..core.scoring import compute_gem_score

router = APIRouter(prefix="/gems", tags=["gems"])


@dataclass
class GemEntry:
    card_id: str
    name: str
    set_code: str
    set_name: str
    number: str
    rarity: str | None
    image_url: str
    gem_score: float
    median: Money | None
    cheapest_listing: Money | None
    active_listings_count: int | None
    watchers: int | None
    attention_delta_7d: float | None
    trend_pct: float | None
    sample_size: int


def _money_dict(m: Money | None) -> dict[str, Any] | None:
    if m is None:
        return None
    return {"amount": float(m.amount), "currency": m.currency, "display": str(m)}


@router.get("")
def list_gems(
    request: Request,
    limit: int = 50,
    set_code: str | None = None,
    min_value: float | None = None,
) -> dict[str, Any]:
    """Return the highest-gem-score cards from the cached insights map.

    Threshold is configurable so the UI badge stays calibrated when the catalogue
    is small. Default returns the top ``limit`` by gem_score, ignoring zeros.
    """
    insights: dict[str, dict[str, Any]] = getattr(request.app.state, "card_insights", {}) or {}
    catalogue = request.app.state.catalogue
    out: list[dict[str, Any]] = []
    for card_id, info in insights.items():
        card = catalogue.get(card_id) if hasattr(catalogue, "get") else None
        if card is None:
            continue
        if set_code and card.set_code != set_code:
            continue
        median = info.get("median")
        if min_value is not None and (median is None or median.get("amount", 0) < min_value):
            continue
        score = info.get("gem_score")
        if score is None or score <= 0:
            continue
        out.append({
            "card": {
                "id": card.id,
                "name": card.name,
                "set_code": card.set_code,
                "set_name": card.set_name,
                "number": card.number,
                "rarity": card.rarity,
            },
            "image_url": card.image_url,
            "gem_score": round(float(score), 2),
            "median": median,
            "cheapest_listing": info.get("cheapest_listing"),
            "active_listings_count": info.get("active_listings_count"),
            "watchers": info.get("watchers"),
            "attention_delta_7d": info.get("attention_delta_7d"),
            "trend_pct": info.get("trend_pct"),
            "sample_size": int(info.get("sample_size") or 0),
        })
    out.sort(key=lambda x: x["gem_score"], reverse=True)
    return {"gems": out[:limit], "threshold": 0.0}


def update_card_insights(app: Any, deals: list[Any]) -> None:
    """Fold a scan's deals into the persistent insights map keyed by card id.

    Stored: latest median + cheapest listing + active-listings count + cached gem
    score per card. Cards re-seen later overwrite; this map is the source of truth
    for the Browse-tile badges and ``GET /gems``. Bumped from a tiny helper here
    because the alternative would scatter it through every scan call-site.
    """
    insights: dict[str, dict[str, Any]] = getattr(app.state, "card_insights", None) or {}
    for deal in deals:
        card = deal.identification.card
        if card is None or deal.valuation is None:
            continue
        listing_price = (
            deal.listing.current_bid_price
            if (deal.listing.buying_format.value == "AUCTION" and deal.listing.current_bid_price)
            else deal.listing.price
        )
        # Recompute the gem score from current evidence even if the deal lacked it
        # (e.g. older scans), so the cache is always consistent with the function.
        score = deal.gem_score or compute_gem_score(
            estimated_value=float(deal.valuation.median.amount),
            confidence=deal.confidence,
            sell_probability=deal.sell_probability,
            active_listings=deal.active_listings_count,
            sample_size=deal.valuation.sample_size,
            trend_pct=deal.trend_pct,
            watchers=deal.watchers,
            attention_delta_7d=deal.attention_delta_7d,
        )
        prev = insights.get(card.id, {})
        cheapest = prev.get("cheapest_listing")
        cheapest_money = (
            listing_price
            if (cheapest is None or float(listing_price.amount) < cheapest.get("amount", 1e9))
            else None
        )
        insights[card.id] = {
            "median": _money_dict(deal.valuation.median),
            "market_value": _money_dict(deal.valuation.median),
            "cheapest_listing": (
                _money_dict(cheapest_money) if cheapest_money is not None else cheapest
            ),
            "active_listings_count": deal.active_listings_count,
            "watchers": deal.watchers,
            "attention_delta_7d": deal.attention_delta_7d,
            "trend_pct": deal.trend_pct,
            "sample_size": deal.valuation.sample_size,
            "gem_score": round(float(score), 2) if score else 0.0,
        }
    app.state.card_insights = insights
