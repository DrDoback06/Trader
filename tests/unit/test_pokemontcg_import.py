from __future__ import annotations

from pathlib import Path

from trader.tools.import_pokemontcg import (
    card_number,
    group_to_sets,
    set_code,
    to_catalogue_card,
    write_sets,
)

MEW = {"id": "sv3pt5", "name": "151", "ptcgoCode": "MEW", "printedTotal": 165, "total": 207}
PROMO = {"id": "svp", "name": "SVP Black Star Promos"}


def test_set_code_prefers_ptcgo_else_id() -> None:
    assert set_code(MEW) == "MEW"
    assert set_code({"id": "base1", "name": "Base"}) == "BASE1"


def test_card_number_numbered_and_promo() -> None:
    assert card_number({"number": "199"}, MEW) == "199/165"
    assert card_number({"number": "6"}, MEW) == "6/165"
    assert card_number({"number": "SWSH001"}, PROMO) == "SWSH001"


def test_to_catalogue_card() -> None:
    card = to_catalogue_card(
        {"number": "199", "name": "Charizard ex", "rarity": "Special Illustration Rare", "set": MEW}
    )
    assert card == {
        "number": "199/165",
        "name": "Charizard ex",
        "rarity": "Special Illustration Rare",
    }


def test_group_and_write(tmp_path: Path) -> None:
    cards = [
        {"number": "199", "name": "Charizard ex", "set": MEW},
        {"number": "6", "name": "Charizard", "set": MEW},
        {"number": "SWSH001", "name": "Celebi V", "set": PROMO},
        {"number": "10", "name": "", "set": MEW},  # no name -> skipped
    ]
    sets = group_to_sets(cards)
    assert set(sets) == {"MEW", "SVP"}
    assert len(sets["MEW"]["cards"]) == 2

    assert write_sets(sets, tmp_path) == 2
    assert (tmp_path / "MEW.json").exists()
