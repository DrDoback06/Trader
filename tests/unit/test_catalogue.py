from __future__ import annotations

from trader.core.models import Card, Game
from trader.identify.catalogue import Catalogue, canon_number, name_tokens


def _card(set_code: str, number: str, name: str) -> Card:
    return Card(
        id=f"POKEMON-{set_code}-{number}",
        game=Game.POKEMON,
        set_code=set_code,
        set_name=set_code,
        number=number,
        name=name,
    )


def test_canon_number() -> None:
    assert canon_number("006/165") == "6/165"
    assert canon_number("SWSH001") == "SWSH001"


def test_name_tokens_drops_stopwords() -> None:
    assert name_tokens("Charizard ex") == ["charizard"]
    assert "mew" in name_tokens("Mew ex")


def test_candidates_number_then_name_then_fallback() -> None:
    cat = Catalogue(
        [
            _card("MEW", "199/165", "Charizard ex"),
            _card("OBF", "125/197", "Charizard ex"),
            _card("MEW", "173/165", "Pikachu"),
        ]
    )

    # Number present -> numerator filter picks the exact set.
    by_num = cat.candidates("199/165", "Charizard ex")
    assert len(by_num) == 1 and by_num[0].set_code == "MEW"

    # No number -> name-token prefilter returns both Charizards (not Pikachu).
    by_name = cat.candidates(None, "Charizard ex")
    assert {c.set_code for c in by_name} == {"MEW", "OBF"}

    # Unknown name -> falls back to the whole game.
    assert len(cat.candidates(None, "Zzz Nonexistent")) == 3
