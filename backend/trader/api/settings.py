"""Settings endpoints — view and tweak the buy rules, re-running the pipeline.

In Phase 1 the rules live in memory and editing them re-evaluates the demo deals,
so you can see the guardrails take effect immediately. Persistence arrives in
Phase 4.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel

from ..core.money import Money
from ..services.demo import build_demo_deals
from .serialize import ruleset_to_dict

router = APIRouter(prefix="/settings", tags=["settings"])


class RuleSetIn(BaseModel):
    total_budget: float | None = None
    max_spend_per_card: float | None = None
    min_profit: float | None = None
    min_market_value: float | None = None
    min_roi: float | None = None
    min_margin: float | None = None
    min_confidence: float | None = None
    min_sell_probability: float | None = None
    min_annualised_roi: float | None = None


@router.get("")
def get_settings(request: Request) -> dict[str, Any]:
    return ruleset_to_dict(request.app.state.pipeline_cfg.rules)


@router.put("")
def update_settings(request: Request, body: RuleSetIn) -> dict[str, Any]:
    rules = request.app.state.pipeline_cfg.rules
    if body.total_budget is not None:
        rules.total_budget = Money.gbp(body.total_budget)
    if body.max_spend_per_card is not None:
        rules.max_spend_per_card = Money.gbp(body.max_spend_per_card)
    if body.min_profit is not None:
        rules.min_profit = Money.gbp(body.min_profit)
    if body.min_market_value is not None:
        rules.min_market_value = Money.gbp(body.min_market_value)
    if body.min_roi is not None:
        rules.min_roi = body.min_roi
    if body.min_margin is not None:
        rules.min_margin = body.min_margin
    if body.min_confidence is not None:
        rules.min_confidence = body.min_confidence
    if body.min_sell_probability is not None:
        rules.min_sell_probability = body.min_sell_probability
    if body.min_annualised_roi is not None:
        rules.min_annualised_roi = body.min_annualised_roi

    # Re-run the pipeline so the dashboard reflects the new guardrails immediately.
    request.app.state.deals = build_demo_deals(request.app.state.pipeline_cfg)
    return ruleset_to_dict(rules)
