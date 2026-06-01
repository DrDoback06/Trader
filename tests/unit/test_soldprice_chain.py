from __future__ import annotations

import httpx
import pytest

from trader.core.models import Card, Game, Valuation
from trader.core.money import Money
from trader.providers.soldprice_chain import ChainSoldPriceProvider

CARD = Card(
    id="POKEMON-MEW-199/165",
    game=Game.POKEMON,
    set_code="MEW",
    set_name="151",
    number="199/165",
    name="Charizard ex",
)


class _Stub:
    def __init__(self, name: str, value: float | None = None, *, raises: bool = False) -> None:
        self.name = name
        self._value = value
        self._raises = raises
        self.calls = 0

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        self.calls += 1
        if self._raises:
            raise httpx.HTTPStatusError(
                "boom", request=httpx.Request("GET", "http://x"),
                response=httpx.Response(429),
            )
        if self._value is None:
            return None
        return Valuation(card.id, condition_key, self.name, Money.gbp(self._value))


def test_first_hit_wins_and_short_circuits() -> None:
    first, second = _Stub("a", 50.0), _Stub("b", 99.0)
    chain = ChainSoldPriceProvider([first, second])
    val = chain.get_valuation(CARD, "RAW_NM")
    assert val is not None and val.provider == "a"
    assert second.calls == 0  # never consulted once 'a' produced a value


def test_falls_through_to_next_on_none() -> None:
    first, second = _Stub("a", None), _Stub("b", 99.0)
    val = ChainSoldPriceProvider([first, second]).get_valuation(CARD, "RAW_NM")
    assert val is not None and val.provider == "b"


def test_skips_erroring_provider_then_values() -> None:
    # RapidAPI out of quota (raises) -> free source still returns a value.
    rapid, free = _Stub("ebay_uk_sold", raises=True), _Stub("pokemontcg_market", 42.0)
    val = ChainSoldPriceProvider([rapid, free]).get_valuation(CARD, "RAW_NM")
    assert val is not None and val.provider == "pokemontcg_market"


def test_raises_when_every_provider_errors() -> None:
    chain = ChainSoldPriceProvider([_Stub("a", raises=True), _Stub("b", raises=True)])
    with pytest.raises(httpx.HTTPError):
        chain.get_valuation(CARD, "RAW_NM")


def test_returns_none_when_all_miss() -> None:
    chain = ChainSoldPriceProvider([_Stub("a", None), _Stub("b", None)])
    assert chain.get_valuation(CARD, "RAW_NM") is None
