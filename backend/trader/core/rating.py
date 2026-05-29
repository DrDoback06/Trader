"""Fast-triage indicators: profit traffic-light, market discount, sell-through.

These are *indicators* for eyeballing deals quickly, not promises:

- ``profit_tier``  GREEN/AMBER/RED from ROI, so high-profit deals jump out.
- ``discount_vs_market``  how far below market value you're buying.
- ``sell_probability``  a rough chance the card actually sells near market value,
  driven by liquidity (how many comparable cards sell) and price stability. It
  gets sharper in later phases with real sales-velocity data — for now it's an
  early indicator so we can prioritise deals that will actually convert to cash.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from .economics import EconomicsResult


class Tier(StrEnum):
    GREEN = "GREEN"
    AMBER = "AMBER"
    RED = "RED"


@dataclass(frozen=True)
class RatingConfig:
    # Profit traffic-light thresholds, by ROI (profit / buy cost).
    green_roi: float = 0.40
    amber_roi: float = 0.20
    # Sell-through traffic-light thresholds, by probability.
    green_sell: float = 0.66
    amber_sell: float = 0.40
    # Sell-through model.
    full_liquidity_samples: int = 20  # sold-comp count at which liquidity saturates
    full_liquidity_sales_per_week: float = 3.0  # sales/week at which liquidity saturates
    max_spread: float = 1.2  # price spread at which stability hits its floor
    spread_floor: float = 0.25


def profit_tier(roi: float, cfg: RatingConfig | None = None) -> Tier:
    cfg = cfg or RatingConfig()
    if roi >= cfg.green_roi:
        return Tier.GREEN
    if roi >= cfg.amber_roi:
        return Tier.AMBER
    return Tier.RED


def sell_tier(probability: float, cfg: RatingConfig | None = None) -> Tier:
    cfg = cfg or RatingConfig()
    if probability >= cfg.green_sell:
        return Tier.GREEN
    if probability >= cfg.amber_sell:
        return Tier.AMBER
    return Tier.RED


def discount_vs_market(econ: EconomicsResult) -> float:
    """Fraction below market you're buying at: (est_value - buy_cost) / est_value."""
    value = econ.resale_gross.amount
    if value <= 0:
        return 0.0
    return float((value - econ.buy_cost.amount) / value)


def price_trend(current: float, earlier: float | None) -> float | None:
    """Fractional change in market value vs an earlier sample (rising = positive).
    Buying into momentum: today's comp is already stale if the card is climbing."""
    if earlier is None or earlier <= 0:
        return None
    return (current - earlier) / earlier


def annualised_roi(roi: float, days_to_sell: float | None) -> float | None:
    """ROI scaled by how often the capital turns over in a year. The real money
    metric: a 20% flip in 5 days beats a 60% flip that sits for 6 months."""
    if days_to_sell is None or days_to_sell <= 0:
        return None
    return roi * (365.0 / days_to_sell)


def sell_probability(
    sample_size: int,
    spread: float,
    *,
    target_ratio: float = 1.0,
    sales_per_week: float | None = None,
    cfg: RatingConfig | None = None,
) -> float:
    """Rough probability of selling near market value, in ``[0, 1]``.

    ``sales_per_week`` (real velocity) is preferred for the liquidity estimate when
    available, else we fall back to the sold-comp ``sample_size``. ``target_ratio``
    = planned resale price / median (1.0 = list at market; below 1.0 sells easier).
    """
    cfg = cfg or RatingConfig()

    if sales_per_week is not None and cfg.full_liquidity_sales_per_week > 0:
        liquidity = min(1.0, max(0.0, sales_per_week) / cfg.full_liquidity_sales_per_week)
    elif cfg.full_liquidity_samples > 0:
        liquidity = min(1.0, max(0, sample_size) / cfg.full_liquidity_samples)
    else:
        liquidity = 1.0

    if spread <= 0:
        stability = 1.0
    else:
        fraction = min(1.0, spread / cfg.max_spread)
        stability = max(cfg.spread_floor, 1.0 - fraction * (1.0 - cfg.spread_floor))

    if target_ratio > 1.0:
        pricing = max(0.3, 1.0 - (target_ratio - 1.0))
    elif target_ratio < 1.0:
        pricing = min(1.0, 1.0 + (1.0 - target_ratio) * 0.5)
    else:
        pricing = 1.0

    return max(0.0, min(1.0, liquidity * stability * pricing))
