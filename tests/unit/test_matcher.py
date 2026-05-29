from __future__ import annotations

from trader.core.models import ConditionBucket, Decision
from trader.identify.catalogue import Catalogue
from trader.identify.matcher import identify
from trader.identify.parser import parse_listing


def _id(title: str, catalogue: Catalogue) -> object:
    return identify(parse_listing(title), catalogue, ConditionBucket.RAW_NM)


def test_exact_match(catalogue: Catalogue) -> None:
    result = identify(
        parse_listing("Pokemon 151 Charizard ex 199/165 Near Mint"),
        catalogue,
        ConditionBucket.RAW_NM,
    )
    assert result.decision is Decision.MATCHED
    assert result.card is not None
    assert result.card.number == "199/165"
    assert result.match_score > 0.9


def test_number_disambiguates_same_name_across_sets(catalogue: Catalogue) -> None:
    """Charizard exists in MEW (6/165), BS (4/102), OBF... the number decides."""
    result = identify(parse_listing("Charizard 4/102 holo"), catalogue, ConditionBucket.RAW_NM)
    assert result.decision is Decision.MATCHED
    assert result.card is not None
    assert result.card.set_code == "BS"
    assert result.card.number == "4/102"


def test_hard_flag_is_rejected_even_with_good_name(catalogue: Catalogue) -> None:
    result = identify(
        parse_listing("Charizard ex 199/165 joblot bundle x40"),
        catalogue,
        ConditionBucket.RAW_NM,
    )
    assert result.decision is Decision.REJECTED


def test_unknown_card_number_is_rejected(catalogue: Catalogue) -> None:
    result = identify(parse_listing("Snorlax 100/100 holo"), catalogue, ConditionBucket.RAW_NM)
    assert result.decision is Decision.REJECTED


def test_ambiguous_when_two_candidates_tie(catalogue: Catalogue) -> None:
    # Two "Mew ex" printings (151/165 and 205/165); with no number we can't choose.
    result = identify(parse_listing("Pokemon Mew ex"), catalogue, ConditionBucket.RAW_NM)
    assert result.decision is Decision.AMBIGUOUS
