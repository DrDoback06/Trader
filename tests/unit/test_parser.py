from __future__ import annotations

from trader.core.models import GradeCompany
from trader.identify.parser import parse_listing


def test_clean_title() -> None:
    p = parse_listing("Pokemon 151 Charizard ex 199/165 Special Illustration Rare Near Mint")
    assert p.number == "199/165"
    assert "charizard" in p.name.lower()
    assert "ex" in p.name.lower().split()
    assert p.language == "English"
    assert not p.is_graded
    assert p.flags == []


def test_card_number_is_canonicalised() -> None:
    assert parse_listing("Charizard 006/165 Pokemon 151").number == "6/165"


def test_promo_number() -> None:
    assert parse_listing("Pikachu SWSH050 promo").number == "SWSH050"


def test_graded_detection() -> None:
    p = parse_listing("Pikachu 173/165 PSA 10 GEM MINT Pokemon 151")
    assert p.is_graded
    assert p.grade_company is GradeCompany.PSA
    assert p.grade_value == 10.0


def test_graded_half_grade() -> None:
    p = parse_listing("Charizard CGC 9.5 base set 4/102")
    assert p.is_graded
    assert p.grade_company is GradeCompany.CGC
    assert p.grade_value == 9.5


def test_language_detection() -> None:
    assert parse_listing("Charizard ex 199/165 Japanese").language == "Japanese"


def test_lot_flag() -> None:
    assert "LOT" in parse_listing("Pokemon 151 Joblot Bundle x30 cards").flags


def test_proxy_flag() -> None:
    assert "PROXY" in parse_listing("Charizard ex 199/165 proxy custom").flags


def test_damaged_flag() -> None:
    assert "DAMAGED" in parse_listing("Charizard 6/165 heavily played creased").flags


def test_item_specifics_take_priority() -> None:
    p = parse_listing(
        "messy title here",
        {"Card Name": "Charizard ex", "Card Number": "199/165", "Language": "English"},
    )
    assert p.name == "Charizard ex"
    assert p.number == "199/165"
