"""Card search: value live listings against the *searched* card, not their titles.

These prove the two fixes:
- valuation uses the clean searched-card identity (so it actually returns a value),
- smart number matching drops wrong variants but keeps number-less name matches.
"""

from __future__ import annotations

from typing import Any

from trader.core.models import ListingFacts
from trader.core.money import Money
from trader.services.pipeline import (
    PipelineConfig,
    _numbers_match,
    evaluate_against_card,
    resolve_searched_card,
)


def _listing(title: str, *, price: float = 45.0, ext: str = "x1") -> ListingFacts:
    return ListingFacts(
        external_id=ext,
        title=title,
        price=Money.gbp(price),
        condition_raw="Used",
        url=f"https://www.ebay.co.uk/itm/{ext}",
    )


def test_numbers_match_rules() -> None:
    assert _numbers_match("199/165", "199/165") is True
    assert _numbers_match("58/198", "058/198") is True  # canonicalised
    assert _numbers_match("199/166", "199/165") is True  # same collector no, diff total
    assert _numbers_match("12/165", "199/165") is False
    assert _numbers_match("199/165", "") is True  # searched card has no number => keep


def test_resolve_uses_catalogue_when_present(catalogue: Any) -> None:
    card = resolve_searched_card("Charizard ex 199/165", catalogue, PipelineConfig())
    assert card.id == "POKEMON-MEW-199/165"
    assert card.number == "199/165"
    assert card.set_name  # canonical set name => better sold-price query


def test_resolve_builds_clean_card_from_query_when_absent(catalogue: Any) -> None:
    card = resolve_searched_card("Mystery Beast 900/900", catalogue, PipelineConfig())
    assert card.id.startswith("SEARCH:")
    assert card.number == "900/900"
    # the name comes from the typed query, never a noisy listing title
    assert "Beast" in card.name


def test_values_noisy_listing_against_searched_card(catalogue: Any, sold_provider: Any) -> None:
    cfg = PipelineConfig()
    card = resolve_searched_card("Charizard ex 199/165", catalogue, cfg)
    # A title too noisy to value on its own, but it states the right number.
    listing = _listing("POKEMON 151 Charizard ex 199/165 ULTRA RARE NM L@@K")
    deal = evaluate_against_card(listing, card, sold_provider, cfg)
    assert deal is not None
    assert deal.valuation is not None
    assert float(deal.valuation.median.amount) == 80.0  # fixture RAW_NM median
    assert deal.economics is not None


def test_drops_wrong_number_variant(catalogue: Any, sold_provider: Any) -> None:
    cfg = PipelineConfig()
    card = resolve_searched_card("Charizard ex 199/165", catalogue, cfg)
    listing = _listing("Charizard ex 12/165 reverse holo Near Mint")
    assert evaluate_against_card(listing, card, sold_provider, cfg) is None


def test_keeps_numberless_name_match(catalogue: Any, sold_provider: Any) -> None:
    cfg = PipelineConfig()
    card = resolve_searched_card("Charizard ex 199/165", catalogue, cfg)
    listing = _listing("Charizard ex 151 Near Mint")  # no number => eBay name-matched
    deal = evaluate_against_card(listing, card, sold_provider, cfg)
    assert deal is not None
    assert deal.valuation is not None


def test_drops_hard_flagged_listing(catalogue: Any, sold_provider: Any) -> None:
    cfg = PipelineConfig()
    card = resolve_searched_card("Charizard ex 199/165", catalogue, cfg)
    listing = _listing("Charizard ex 199/165 PROXY custom card")
    assert evaluate_against_card(listing, card, sold_provider, cfg) is None
