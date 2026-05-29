"""Deal scoring and ranking.

The headline score is **risk-adjusted expected profit**: ``profit × confidence``.
A nominally bigger margin on a shakily-identified card should not outrank a solid,
well-identified flip. Ties break on ROI.
"""

from __future__ import annotations

from .economics import EconomicsResult
from .models import Deal


def deal_score(economics: EconomicsResult, confidence: float) -> float:
    """Risk-adjusted expected profit in the deal's currency units (e.g. £)."""
    return round(economics.profit.as_float * confidence, 4)


def rank_deals(deals: list[Deal]) -> list[Deal]:
    """Best first: rule-passing deals, then score, then ROI."""

    def key(d: Deal) -> tuple[bool, float, float]:
        roi = d.economics.roi if d.economics is not None else 0.0
        return (d.passed_rules, d.score, roi)

    return sorted(deals, key=key, reverse=True)
