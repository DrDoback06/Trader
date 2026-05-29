from __future__ import annotations

from collections.abc import Callable

from trader.core.economics import EconomicsResult
from trader.core.models import Deal
from trader.core.money import Money
from trader.core.scoring import deal_score, rank_deals


def _econ(profit: float, roi: float) -> EconomicsResult:
    return EconomicsResult(
        buy_cost=Money.gbp(10),
        resale_gross=Money.gbp(20),
        selling_fees=Money.zero(),
        outbound_postage=Money.zero(),
        packaging=Money.zero(),
        net_proceeds=Money.gbp(10 + profit),
        profit=Money.gbp(profit),
        roi=roi,
        margin=0.3,
    )


def test_deal_score_is_risk_adjusted_profit() -> None:
    assert deal_score(_econ(10, 1.0), 0.5) == 5.0
    assert deal_score(_econ(10, 1.0), 1.0) == 10.0
    # sell-through probability further discounts the score
    assert deal_score(_econ(10, 1.0), 1.0, 0.5) == 5.0
    assert deal_score(_econ(10, 1.0), 0.5, 0.5) == 2.5


def test_rank_passing_first_then_score_then_roi(make_deal: Callable[..., Deal]) -> None:
    low = make_deal(profit=5, roi=0.3, margin=0.2, confidence=0.9)
    low.passed_rules = True
    low.score = 4.5
    high = make_deal(profit=20, roi=0.5, margin=0.3, confidence=0.9)
    high.passed_rules = True
    high.score = 18.0
    failing = make_deal(profit=100, roi=2.0, margin=0.9, confidence=0.9)
    failing.passed_rules = False
    failing.score = 90.0  # high score but failed rules

    ranked = rank_deals([low, failing, high])
    assert [d.score for d in ranked] == [18.0, 4.5, 90.0]
    assert ranked[-1] is failing  # rule-failing deal sinks below passing ones
