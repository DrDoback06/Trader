from __future__ import annotations

from collections.abc import Callable

from trader.core.models import Card, Deal, ListingFacts, Valuation
from trader.core.money import Money
from trader.core.rules import GradedPolicy, RuleSet, evaluate
from trader.identify.catalogue import Catalogue
from trader.services.pipeline import PipelineConfig, evaluate_listing
from trader.services.watchlist import graded_sweep_targets


def test_for_holds_profile() -> None:
    rules = RuleSet.for_holds()
    assert rules.graded_policy is GradedPolicy.GRADED_ONLY
    assert rules.min_discount == 0.12
    assert rules.min_sell_probability == 0.0  # holds may be illiquid
    assert rules.min_roi < 0.25  # lower bar than a quick flip


def test_min_discount_gate(make_deal: Callable[..., Deal]) -> None:
    deal = make_deal(profit=15, roi=0.6, margin=0.35, confidence=0.8, buy_cost=40)
    deal.discount = 0.05  # only 5% below market
    ok, reasons = evaluate(deal, RuleSet(min_discount=0.12))
    assert not ok
    assert any("discount" in r for r in reasons)


def test_graded_sweep_covers_grades() -> None:
    queries = [t.query for t in graded_sweep_targets()]
    assert "pokemon PSA 9" in queries
    assert "pokemon CGC 8" in queries
    assert "pokemon PSA 10" in queries
    assert len(queries) == 10  # 2 graders x 5 grades


class _GradedProvider:
    name = "g"

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        if condition_key == "GRADED_PSA_9":
            return Valuation(
                card_id=card.id, condition_key=condition_key, provider="g",
                median=Money.gbp(120), sample_size=10,
            )
        return None


def test_pipeline_values_psa9_slab_as_hold(catalogue: Catalogue) -> None:
    listing = ListingFacts(
        external_id="h1",
        title="Pokemon 151 Charizard ex 199/165 PSA 9",
        price=Money.gbp(80),  # well below the £120 PSA 9 market
        condition_raw="Graded",
    )
    deal = evaluate_listing(
        listing, catalogue, _GradedProvider(), PipelineConfig(rules=RuleSet.for_holds())
    )
    assert deal.identification.is_graded
    assert deal.valuation is not None
    assert deal.valuation.condition_key == "GRADED_PSA_9"
    assert deal.hold_candidate is True  # grade 9 (<10), bought below market
    assert deal.passed_rules is True  # clears the hold ruleset
