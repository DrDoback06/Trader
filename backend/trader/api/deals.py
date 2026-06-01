"""Deals endpoints — the ranked opportunities the dashboard renders."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from ..core.models import BuyingFormat
from .serialize import deal_to_dict

router = APIRouter(prefix="/deals", tags=["deals"])


def _ends_within(deal: Any, hours: float) -> bool:
    end_iso = deal.listing.item_end_date
    if not end_iso:
        return False
    try:
        end = datetime.fromisoformat(end_iso.replace("Z", "+00:00"))
    except ValueError:
        return False
    now = datetime.now(tz=timezone.utc)
    return now <= end <= now + timedelta(hours=hours)


@router.get("")
def list_deals(
    request: Request,
    only_passing: bool = False,
    mode: str = "all",
    within_hours: float = 2.0,
) -> list[dict[str, Any]]:
    """List the ranked deals.

    ``mode`` filters server-side:
    * ``all`` (default) — every deal.
    * ``sniper`` — auctions ending within ``within_hours`` with a positive bid floor.
    * ``gems`` — deals with a hidden-gem score above zero (low listing saturation × high value).
    """
    deals = list(request.app.state.deals)
    if only_passing:
        deals = [d for d in deals if d.passed_rules]
    if mode == "sniper":
        deals = [
            d for d in deals
            if d.listing.buying_format == BuyingFormat.AUCTION
            and _ends_within(d, within_hours)
            and (d.max_bid is None or d.max_bid.amount > 0)
        ]
        deals.sort(
            key=lambda d: d.listing.item_end_date or ""
        )
    elif mode == "gems":
        deals = [d for d in deals if (getattr(d, "gem_score", 0) or 0) > 0]
        deals.sort(key=lambda d: getattr(d, "gem_score", 0) or 0, reverse=True)
    return [deal_to_dict(d) for d in deals]


@router.get("/{external_id}")
def get_deal(request: Request, external_id: str) -> dict[str, Any]:
    for d in request.app.state.deals:
        if d.listing.external_id == external_id:
            return deal_to_dict(d)
    raise HTTPException(status_code=404, detail="deal not found")
