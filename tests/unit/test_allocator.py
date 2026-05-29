from __future__ import annotations

from collections.abc import Callable

from trader.core.allocator import allocate
from trader.core.models import Deal
from trader.core.money import Money


def _deal(make_deal: Callable[..., Deal], ext: str, buy_cost: float, score: float) -> Deal:
    d = make_deal(profit=10, roi=0.5, margin=0.3, confidence=0.8, buy_cost=buy_cost)
    d.passed_rules = True
    d.score = score
    d.listing.external_id = ext
    return d


def test_allocator_picks_best_basket_within_budget(make_deal: Callable[..., Deal]) -> None:
    # densities: a=18/40=.45, b=8/30=.27, c=4/50=.08 -> greedy takes a then b (70 <= 80).
    deals = [
        _deal(make_deal, "a", 40, 18),
        _deal(make_deal, "b", 30, 8),
        _deal(make_deal, "c", 50, 4),
    ]
    alloc = allocate(deals, Money.gbp(80))
    assert {d.listing.external_id for d in alloc.chosen} == {"a", "b"}
    assert alloc.total_cost.amount <= 80
    assert alloc.skipped_over_budget == 1


def test_allocator_ignores_failing_and_zero_score(make_deal: Callable[..., Deal]) -> None:
    failing = _deal(make_deal, "x", 40, 18)
    failing.passed_rules = False
    assert allocate([failing], Money.gbp(300)).chosen == []
