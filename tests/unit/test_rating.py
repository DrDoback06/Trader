from __future__ import annotations

import pytest

from trader.core.economics import EconomicsResult
from trader.core.money import Money
from trader.core.rating import (
    RatingConfig,
    Tier,
    annualised_roi,
    discount_vs_market,
    profit_tier,
    sell_probability,
    sell_tier,
)


def _econ(buy: float, value: float, roi: float = 0.0) -> EconomicsResult:
    return EconomicsResult(
        buy_cost=Money.gbp(buy),
        resale_gross=Money.gbp(value),
        selling_fees=Money.zero(),
        outbound_postage=Money.zero(),
        packaging=Money.zero(),
        net_proceeds=Money.zero(),
        profit=Money.gbp(value - buy),
        roi=roi,
        margin=0.0,
    )


def test_profit_tier_thresholds() -> None:
    assert profit_tier(0.50) is Tier.GREEN
    assert profit_tier(0.40) is Tier.GREEN
    assert profit_tier(0.25) is Tier.AMBER
    assert profit_tier(0.05) is Tier.RED
    assert profit_tier(-0.5) is Tier.RED


def test_sell_tier_thresholds() -> None:
    assert sell_tier(0.90) is Tier.GREEN
    assert sell_tier(0.50) is Tier.AMBER
    assert sell_tier(0.10) is Tier.RED


def test_discount_vs_market() -> None:
    assert discount_vs_market(_econ(60, 100)) == pytest.approx(0.40)
    assert discount_vs_market(_econ(0, 0)) == 0.0  # divide-by-zero guard


def test_sell_probability_bounds_and_monotonicity() -> None:
    cfg = RatingConfig()
    assert 0.0 <= sell_probability(0, 0.0, cfg=cfg) <= 1.0
    # more sold comps => more liquid => higher
    assert sell_probability(20, 0.2, cfg=cfg) > sell_probability(4, 0.2, cfg=cfg)
    # wider price spread => less stable => lower
    assert sell_probability(20, 0.1, cfg=cfg) > sell_probability(20, 1.0, cfg=cfg)
    # saturates near 1 with many comps and a tight spread
    assert sell_probability(40, 0.0, cfg=cfg) == pytest.approx(1.0)


def test_annualised_roi() -> None:
    assert annualised_roi(0.30, None) is None
    assert annualised_roi(0.30, 0) is None
    assert annualised_roi(0.30, 73.0) == pytest.approx(0.30 * 5.0, abs=1e-6)  # 365/73 = 5


def test_sell_probability_prefers_real_velocity() -> None:
    cfg = RatingConfig()
    slow = sell_probability(20, 0.2, sales_per_week=0.2, cfg=cfg)
    fast = sell_probability(20, 0.2, sales_per_week=5.0, cfg=cfg)
    assert fast > slow


def test_pricing_below_market_sells_more_easily() -> None:
    cfg = RatingConfig()
    at_market = sell_probability(20, 0.3, target_ratio=1.0, cfg=cfg)
    below = sell_probability(20, 0.3, target_ratio=0.8, cfg=cfg)
    above = sell_probability(20, 0.3, target_ratio=1.3, cfg=cfg)
    assert below >= at_market >= above
