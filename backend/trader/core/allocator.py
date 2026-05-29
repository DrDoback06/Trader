"""Capital allocation: with a limited budget, pick the *basket* of deals that
maximises expected profit — not just the single best deal.

A greedy knapsack by value-density (risk-adjusted score per £ of buy cost), which
is a good, fast heuristic for ranking which deals to actually buy first.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from .models import Deal
from .money import Money


@dataclass(frozen=True)
class Allocation:
    chosen: list[Deal]
    total_cost: Money
    total_expected_profit: float  # sum of risk-adjusted scores of chosen deals
    skipped_over_budget: int


def _density(deal: Deal) -> float:
    cost = deal.economics.buy_cost.amount if deal.economics else Decimal("0")
    return deal.score / float(cost) if cost > 0 else 0.0


def allocate(deals: list[Deal], budget: Money) -> Allocation:
    """Choose the highest expected-profit basket of passing deals within ``budget``."""
    candidates = [
        d for d in deals if d.passed_rules and d.economics is not None and d.score > 0
    ]
    ordered = sorted(candidates, key=_density, reverse=True)

    chosen: list[Deal] = []
    spent = Decimal("0")
    skipped = 0
    for deal in ordered:
        cost = deal.economics.buy_cost.amount  # type: ignore[union-attr]
        if spent + cost <= budget.amount:
            chosen.append(deal)
            spent += cost
        else:
            skipped += 1

    return Allocation(
        chosen=chosen,
        total_cost=Money(spent, budget.currency).quantize(),
        total_expected_profit=round(sum(d.score for d in chosen), 2),
        skipped_over_budget=skipped,
    )
