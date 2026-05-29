from __future__ import annotations

from trader.core.economics import FeeProfile, GradingProfile, compute_grading_economics
from trader.core.models import Card, ListingFacts, Valuation
from trader.core.money import Money
from trader.identify.catalogue import Catalogue
from trader.services.pipeline import PipelineConfig, evaluate_listing


def test_grading_worth_it_for_cheap_raw_high_slab() -> None:
    result = compute_grading_economics(
        raw_buy_cost=Money.gbp(40),
        graded_value=Money.gbp(400),
        fee_profile=FeeProfile.default_uk(),
        grading_profile=GradingProfile.default_uk(),
    )
    assert result.worth_grading is True
    assert result.expected_profit.amount > 0


def test_grading_not_worth_below_min_value() -> None:
    result = compute_grading_economics(
        raw_buy_cost=Money.gbp(20),
        graded_value=Money.gbp(30),  # below the £45 min_graded_value
        fee_profile=FeeProfile.default_uk(),
        grading_profile=GradingProfile.default_uk(),
    )
    assert result.worth_grading is False


class _FakeProvider:
    name = "fake"

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        median = Money.gbp(400) if condition_key.startswith("GRADED_PSA_10") else Money.gbp(50)
        return Valuation(
            card_id=card.id, condition_key=condition_key, provider="fake", median=median,
            sample_size=10,
        )


def test_pipeline_attaches_grading_for_raw_card(catalogue: Catalogue) -> None:
    listing = ListingFacts(
        external_id="g1",
        title="Pokemon 151 Charizard ex 199/165 Near Mint",
        price=Money.gbp(40),
        condition_raw="Near Mint",
    )
    deal = evaluate_listing(listing, catalogue, _FakeProvider(), PipelineConfig())
    assert deal.grading is not None
    assert deal.grading.worth_grading is True
