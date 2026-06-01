from __future__ import annotations

from decimal import Decimal

import httpx
import respx

from trader.core.models import Card, Game
from trader.providers.soldprice_pokemontcg import PokemonTcgPriceProvider

URL = "https://api.pokemontcg.io/v2/cards"

CARD = Card(
    id="POKEMON-MEW-199/165",
    game=Game.POKEMON,
    set_code="MEW",
    set_name="151",
    number="199/165",
    name="Charizard ex",
)


def _provider() -> PokemonTcgPriceProvider:
    # No throttle / instant sleep so unit tests don't wait on the real clock.
    return PokemonTcgPriceProvider(
        eur_gbp=0.85, usd_gbp=0.80, min_interval=0.0, sleep=lambda _: None
    )


@respx.mock
def test_cardmarket_price_converted_to_gbp() -> None:
    route = respx.get(URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "data": [
                    {
                        "id": "mew-199",
                        "name": "Charizard ex",
                        "number": "199",
                        "cardmarket": {"prices": {"trendPrice": 100.0, "lowPrice": 70.0}},
                    }
                ]
            },
        )
    )
    val = _provider().get_valuation(CARD, "RAW_NM")
    # Searches by name + the numerator only ('199', not '199/165').
    assert route.calls.last.request.url.params["q"] == 'name:"Charizard ex" number:"199"'
    assert val is not None
    assert val.provider == "pokemontcg_market"
    assert val.median.amount == Decimal("85.00")  # 100 EUR × 0.85
    assert val.low is not None and val.low.amount == Decimal("59.50")  # 70 × 0.85
    assert val.currency == "GBP"


@respx.mock
def test_condition_multiplier_discounts_played() -> None:
    respx.get(URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "data": [
                    {"name": "Charizard ex", "number": "199",
                     "cardmarket": {"prices": {"trendPrice": 100.0}}}
                ]
            },
        )
    )
    val = _provider().get_valuation(CARD, "RAW_MP")  # 0.70 ladder × 85 GBP NM
    assert val is not None
    assert val.median.amount == Decimal("59.50")


@respx.mock
def test_falls_back_to_tcgplayer_usd() -> None:
    respx.get(URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "data": [
                    {
                        "name": "Charizard ex",
                        "number": "199",
                        "tcgplayer": {"prices": {"holofoil": {"market": 50.0, "low": 40.0}}},
                    }
                ]
            },
        )
    )
    val = _provider().get_valuation(CARD, "RAW_NM")
    assert val is not None
    assert val.median.amount == Decimal("40.00")  # 50 USD × 0.80


@respx.mock
def test_graded_returns_none() -> None:
    # Reference prices are ungraded — graded buckets must defer to real sold comps.
    route = respx.get(URL).mock(return_value=httpx.Response(200, json={"data": []}))
    assert _provider().get_valuation(CARD, "GRADED_PSA_10") is None
    assert not route.called  # short-circuits before any HTTP call


@respx.mock
def test_no_match_returns_none() -> None:
    respx.get(URL).mock(return_value=httpx.Response(200, json={"data": []}))
    assert _provider().get_valuation(CARD, "RAW_NM") is None


@respx.mock
def test_retries_on_429_then_succeeds() -> None:
    route = respx.get(URL).mock(
        side_effect=[
            httpx.Response(429, headers={"Retry-After": "0"}),
            httpx.Response(
                200,
                json={"data": [{"name": "Charizard ex", "number": "199",
                                "cardmarket": {"prices": {"trendPrice": 10.0}}}]},
            ),
        ]
    )
    val = _provider().get_valuation(CARD, "RAW_NM")
    assert val is not None and route.call_count == 2
