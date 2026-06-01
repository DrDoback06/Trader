"""Deal scoring and ranking.

The headline score is **risk-adjusted expected profit**: ``profit × confidence ×
sell_probability``. A nominally bigger margin on a shakily-identified card, or one
that is unlikely to actually sell, should not outrank a solid, liquid flip. Ties
break on ROI.

Alongside the headline score, :func:`compute_gem_score` produces a separate
**hidden-gem** ranking optimised for low-attention listings — cards with high
estimated value but few competing listings, few sold comps and few watchers.
That's a different axis to the headline score (which prefers liquid flips); a
deal can be a "boring but reliable" winner on score while a niche card with one
listing and three weekly comps wins on gem_score.
"""

from __future__ import annotations

from math import sqrt

from .economics import EconomicsResult
from .models import Deal


def deal_score(
    economics: EconomicsResult, confidence: float, sell_probability: float = 1.0
) -> float:
    """Risk-adjusted expected profit in the deal's currency units (e.g. £)."""
    return round(economics.profit.as_float * confidence * sell_probability, 4)


def compute_gem_score(
    *,
    estimated_value: float,
    confidence: float,
    sell_probability: float,
    active_listings: int | None = None,
    sample_size: int = 0,
    trend_pct: float | None = None,
    watchers: int | None = None,
    attention_delta_7d: float | None = None,
) -> float:
    """A hidden-gem score that rewards cards with **high value × low attention**.

    The denominator (active listings + √sample_size) is a saturation penalty: a
    Charizard ex with 200 listings and 30 recent comps is well-priced by the market
    and shouldn't outrank a niche card with 1 listing and 3 comps even if its
    absolute value is bigger. Trend, attention and watchers reshape — but never
    determine — the ranking, so a missing signal never zeroes the score.
    """
    if estimated_value <= 0 or confidence <= 0:
        return 0.0
    listings = max(0, active_listings or 0)
    saturation = 1.0 + listings + sqrt(max(0, sample_size) + 1)
    base = (estimated_value * confidence) / saturation
    trend = 1.0 + max(trend_pct or 0.0, 0.0)
    liquidity = max(sell_probability, 0.1)  # don't zero illiquid niches
    attention = 1.0 + max(min(attention_delta_7d or 0.0, 1.0), 0.0)
    if watchers is None:
        watch_factor = 1.0
    else:
        # 0 watchers = 1.0, 25 watchers = 0.5, 50+ watchers = floor of 0.25.
        watch_factor = max(0.25, 1.0 - watchers / 50.0)
    return round(base * trend * liquidity * attention * watch_factor, 4)


def rank_deals(deals: list[Deal]) -> list[Deal]:
    """Best first: rule-passing deals, then score, then ROI."""

    def key(d: Deal) -> tuple[bool, float, float]:
        roi = d.economics.roi if d.economics is not None else 0.0
        return (d.passed_rules, d.score, roi)

    return sorted(deals, key=key, reverse=True)
