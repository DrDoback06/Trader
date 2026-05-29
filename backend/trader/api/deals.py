"""Deals endpoints — the ranked opportunities the dashboard renders."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request

from .serialize import deal_to_dict

router = APIRouter(prefix="/deals", tags=["deals"])


@router.get("")
def list_deals(request: Request, only_passing: bool = False) -> list[dict[str, Any]]:
    deals = request.app.state.deals
    if only_passing:
        deals = [d for d in deals if d.passed_rules]
    return [deal_to_dict(d) for d in deals]


@router.get("/{external_id}")
def get_deal(request: Request, external_id: str) -> dict[str, Any]:
    for d in request.app.state.deals:
        if d.listing.external_id == external_id:
            return deal_to_dict(d)
    raise HTTPException(status_code=404, detail="deal not found")
