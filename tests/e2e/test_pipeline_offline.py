"""End-to-end: the bundled demo data must produce the expected ranked deals,
entirely offline (no API keys, no network)."""

from __future__ import annotations

from trader.core.rules import RuleSet
from trader.services.demo import build_demo_deals


def _by_id(deals: list, ext_id: str):  # type: ignore[no-untyped-def]
    return next(d for d in deals if d.listing.external_id == ext_id)


def test_expected_passing_set() -> None:
    deals = build_demo_deals()
    passing = {d.listing.external_id for d in deals if d.passed_rules}
    assert passing == {"1001", "1002", "1003"}


def test_top_ranked_is_the_best_charizard() -> None:
    deals = build_demo_deals()
    top = deals[0]
    assert top.passed_rules
    assert top.listing.external_id == "1001"
    assert top.economics is not None
    assert top.economics.profit.amount > 0


def test_lot_and_unknown_are_rejected() -> None:
    deals = build_demo_deals()
    assert "REJECTED" in "; ".join(_by_id(deals, "1006").rule_reasons)  # joblot
    assert "REJECTED" in "; ".join(_by_id(deals, "1009").rule_reasons)  # not in catalogue


def test_japanese_excluded_by_language() -> None:
    deals = build_demo_deals()
    reasons = "; ".join(_by_id(deals, "1007").rule_reasons)
    assert "language" in reasons


def test_overpriced_excluded_by_cap_and_profit() -> None:
    deals = build_demo_deals()
    reasons = "; ".join(_by_id(deals, "1008").rule_reasons)
    assert "per-card cap" in reasons


def test_no_passing_deal_has_excluded_flags_or_low_confidence() -> None:
    rules = RuleSet()
    deals = build_demo_deals()
    for d in deals:
        if d.passed_rules:
            assert not set(d.identification.parsed.flags) & set(rules.exclude_flags)
            assert d.confidence >= rules.min_confidence
            assert d.economics is not None and d.economics.profit.amount > 0
