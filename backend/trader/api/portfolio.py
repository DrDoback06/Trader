"""Capital allocator + portfolio P&L endpoints."""

from __future__ import annotations

from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..core.allocator import allocate
from ..core.money import Money
from ..providers.factory import build_sell_client
from ..services.portfolio import (
    buy_from_deal,
    get_position,
    mark_listed,
    mark_sold,
    portfolio_summary,
)
from ..services.relist import build_listing_draft
from .serialize import deal_to_dict, money_to_dict

router = APIRouter(tags=["portfolio"])


@router.get("/allocate")
def get_allocation(request: Request, budget: float | None = None) -> dict[str, Any]:
    rules = request.app.state.pipeline_cfg.rules
    budget_money = Money.gbp(budget) if budget is not None else rules.total_budget
    alloc = allocate(request.app.state.deals, budget_money)
    return {
        "budget": {"amount": float(budget_money.amount), "display": str(budget_money)},
        "total_cost": {"amount": float(alloc.total_cost.amount), "display": str(alloc.total_cost)},
        "total_expected_profit": alloc.total_expected_profit,
        "skipped_over_budget": alloc.skipped_over_budget,
        "chosen": [deal_to_dict(d) for d in alloc.chosen],
    }


class BuyIn(BaseModel):
    deal_id: str


@router.post("/portfolio/buy")
def buy(request: Request, body: BuyIn) -> dict[str, Any]:
    deal = next(
        (d for d in request.app.state.deals if d.listing.external_id == body.deal_id), None
    )
    if deal is None or deal.economics is None:
        raise HTTPException(status_code=404, detail="deal not found or not priced")
    position_id = buy_from_deal(request.app.state.session_maker, deal)
    return {"position_id": position_id}


class SellIn(BaseModel):
    price: float


@router.post("/portfolio/{position_id}/sell")
def sell(request: Request, position_id: int, body: SellIn) -> dict[str, Any]:
    if not mark_sold(request.app.state.session_maker, position_id, body.price):
        raise HTTPException(status_code=404, detail="position not found")
    return portfolio_summary(request.app.state.session_maker)


@router.get("/portfolio")
def get_portfolio(request: Request) -> dict[str, Any]:
    return portfolio_summary(request.app.state.session_maker)


class RelistIn(BaseModel):
    publish: bool = False
    price: float | None = None
    image_urls: list[str] = []


@router.post("/portfolio/{position_id}/relist")
def relist(request: Request, position_id: int, body: RelistIn) -> dict[str, Any]:
    pos = get_position(request.app.state.session_maker, position_id)
    if pos is None:
        raise HTTPException(status_code=404, detail="position not found")

    settings = request.app.state.settings
    price = (
        Money.gbp(body.price)
        if body.price is not None
        else Money.gbp(round(pos["est_value"] * settings.relist_markup, 2))
    )
    draft = build_listing_draft(
        sku=f"TRDR-{pos['id']}",
        card_name=pos["card_name"],
        number=pos["number"],
        set_name=pos["set_name"],
        grade=pos["grade"],
        condition=pos["condition"],
        price=price,
        category_id=settings.ebay_relist_category_id,
    )
    preview = {
        "sku": draft.sku,
        "title": draft.title,
        "description": draft.description,
        "condition": draft.condition,
        "price": money_to_dict(draft.price),
        "category_id": draft.category_id,
        "grade": draft.grade,
    }

    if not body.publish:
        return {
            "preview": preview,
            "note": "Review, add YOUR OWN photos, then POST again with publish=true and "
            "image_urls=[...] to list it on your eBay account.",
        }

    client = build_sell_client(request.app.state.credentials, settings)
    if client is None:
        raise HTTPException(
            status_code=400,
            detail="Relisting isn't configured. Enable 'eBay relist (Sell API)' and add your "
            "seller token + business-policy IDs under Settings → Sources.",
        )
    if not body.image_urls:
        raise HTTPException(
            status_code=400, detail="Provide image_urls (your own photos) to publish."
        )

    try:
        result = client.relist(draft, body.image_urls)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=502, detail=f"eBay rejected the listing ({exc.response.status_code})."
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach eBay: {exc}") from exc

    mark_listed(request.app.state.session_maker, position_id, result.listing_id or "")
    return {
        "published": True,
        "offer_id": result.offer_id,
        "listing_id": result.listing_id,
        "url": result.url,
        "preview": preview,
    }
