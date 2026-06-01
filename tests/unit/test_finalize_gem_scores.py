"""finalize_gem_scores folds in signals attached after the pipeline runs."""

from __future__ import annotations

from collections.abc import Callable

from trader.core.models import Deal
from trader.services.pipeline import finalize_gem_scores, gem_score_for_deal

_VALUED = {"profit": 20.0, "roi": 1.0, "margin": 0.5, "median": 40.0}


def test_more_active_listings_lowers_gem_score(make_deal: Callable[..., Deal]) -> None:
    few = make_deal(**_VALUED)
    few.active_listings_count = 2
    many = make_deal(**_VALUED)
    many.active_listings_count = 200
    finalize_gem_scores([few, many])
    # A flooded market is a worse "hidden" gem than a scarce one.
    assert few.gem_score > many.gem_score > 0


def test_finalize_recomputes_after_trend_attached(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(**_VALUED)
    finalize_gem_scores([deal])
    flat = deal.gem_score
    deal.trend_pct = 0.5  # price rising 50% — was never folded in before this fix
    finalize_gem_scores([deal])
    assert deal.gem_score > flat


def test_unvalued_deal_scores_zero(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=20.0, roi=1.0, margin=0.5)  # no median -> no valuation
    assert gem_score_for_deal(deal) == 0.0
