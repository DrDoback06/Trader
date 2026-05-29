"""Capital allocator + portfolio P&L endpoints."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..core.allocator import allocate
from ..core.money import Money
from ..services.portfolio import buy_from_deal, mark_sold, portfolio_summary
from .serialize import deal_to_dict

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
