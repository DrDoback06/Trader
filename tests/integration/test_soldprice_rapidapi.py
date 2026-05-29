from __future__ import annotations

import json
from decimal import Decimal

import httpx
import respx

from trader.core.models import Card, Game
from trader.providers.soldprice_rapidapi import RapidApiSoldPriceProvider

HOST = "ebay-average-selling-price.p.rapidapi.com"
URL = f"https://{HOST}/findCompletedItems"

CARD = Card(
    id="POKEMON-MEW-199/165",
    game=Game.POKEMON,
    set_code="MEW",
    set_name="151",
    number="199/165",
    name="Charizard ex",
)


@respx.mock
def test_builds_uk_request_and_parses() -> None:
    route = respx.post(URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "average_price": 82.5,
                "median_price": 80,
                "min_price": 60,
                "max_price": 100,
                "total_results": 24,
                "products": [],
            },
        )
    )
    provider = RapidApiSoldPriceProvider("KEY", host=HOST, site_id="3")
    val = provider.get_valuation(CARD, "RAW_NM")

    req = route.calls.last.request
    assert req.headers["x-rapidapi-key"] == "KEY"
    body = json.loads(req.content)
    assert body["site_id"] == "3"  # eBay UK
    assert "Charizard ex" in body["keywords"]
    assert "199/165" in body["keywords"]

    assert val is not None
    assert val.median.amount == Decimal("80")
    assert val.sample_size == 24
    assert val.spread > 0
    assert val.provider == "ebay_uk_sold"


@respx.mock
def test_graded_query_includes_grade() -> None:
    route = respx.post(URL).mock(
        return_value=httpx.Response(
            200, json={"median_price": 250, "min_price": 200, "max_price": 320, "total_results": 9}
        )
    )
    provider = RapidApiSoldPriceProvider("KEY", host=HOST)
    val = provider.get_valuation(CARD, "GRADED_PSA_10")
    body = json.loads(route.calls.last.request.content)
    assert "PSA" in body["keywords"] and "10" in body["keywords"]
    assert val is not None and val.median.amount == Decimal("250")


@respx.mock
def test_no_results_returns_none() -> None:
    respx.post(URL).mock(
        return_value=httpx.Response(
            200, json={"median_price": 0, "average_price": 0, "total_results": 0}
        )
    )
    provider = RapidApiSoldPriceProvider("KEY", host=HOST)
    assert provider.get_valuation(CARD, "RAW_NM") is None
