from __future__ import annotations

from collections.abc import Callable

from trader.core.models import Deal
from trader.core.money import Money
from trader.core.rules import GradedPolicy, RuleSet, evaluate


def _passing(make_deal: Callable[..., Deal]) -> Deal:
    # Comfortably clears the default RuleSet.
    return make_deal(profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25)


def test_a_good_deal_passes(make_deal: Callable[..., Deal]) -> None:
    ok, reasons = evaluate(_passing(make_deal), RuleSet())
    assert ok
    assert reasons == []


def test_min_profit_enforced(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=1, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25)
    ok, reasons = evaluate(deal, RuleSet())
    assert not ok
    assert any("profit" in r for r in reasons)


def test_min_roi_and_margin_and_confidence(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=15, roi=0.10, margin=0.05, confidence=0.20, buy_cost=25)
    ok, reasons = evaluate(deal, RuleSet())
    assert not ok
    assert any("ROI" in r for r in reasons)
    assert any("margin" in r for r in reasons)
    assert any("confidence" in r for r in reasons)


def test_per_card_cap_and_capital(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=500)
    ok, reasons = evaluate(deal, RuleSet(), available_capital=Money.gbp(100))
    assert not ok
    assert any("per-card cap" in r for r in reasons)
    assert any("available capital" in r for r in reasons)


def test_graded_policy_raw_only(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25, is_graded=True)
    ok, reasons = evaluate(deal, RuleSet(graded_policy=GradedPolicy.RAW_ONLY))
    assert not ok
    assert any("graded" in r for r in reasons)


def test_language_whitelist(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(
        profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25, language="Japanese"
    )
    ok, reasons = evaluate(deal, RuleSet())
    assert not ok
    assert any("language" in r for r in reasons)


def test_excluded_flags(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(
        profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25, flags=["DAMAGED"]
    )
    ok, reasons = evaluate(deal, RuleSet())
    assert not ok
    assert any("flags" in r for r in reasons)


def test_category_whitelist(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(
        profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=25, category_id="999"
    )
    ok, reasons = evaluate(deal, RuleSet(category_whitelist=("183454",)))
    assert not ok
    assert any("category" in r for r in reasons)
