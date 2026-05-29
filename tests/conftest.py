"""Shared test fixtures."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from pathlib import Path

import pytest

import trader
from trader.core.economics import EconomicsResult
from trader.core.models import (
    Card,
    ConditionBucket,
    Deal,
    Decision,
    Game,
    GradeCompany,
    Identification,
    ListingFacts,
    ParsedListing,
)
from trader.core.money import Money
from trader.identify.catalogue import Catalogue
from trader.providers.soldprice_fixture import FixtureSoldPriceProvider

PKG = Path(trader.__file__).resolve().parent


@pytest.fixture
def catalogue() -> Catalogue:
    return Catalogue.from_dir(PKG / "catalogue_data")


@pytest.fixture
def sold_provider() -> FixtureSoldPriceProvider:
    return FixtureSoldPriceProvider.from_file(PKG / "sample_data" / "sold_prices.json")


@pytest.fixture
def make_deal() -> Callable[..., Deal]:
    """Factory for a fully-formed Deal with directly-controlled economics."""

    def _make(
        *,
        profit: float,
        roi: float,
        margin: float,
        confidence: float = 0.9,
        buy_cost: float = 20.0,
        est_value: float = 40.0,
        is_graded: bool = False,
        language: str = "English",
        flags: Iterable[str] = (),
        category_id: str | None = None,
    ) -> Deal:
        econ = EconomicsResult(
            buy_cost=Money.gbp(buy_cost),
            resale_gross=Money.gbp(est_value),
            selling_fees=Money.zero(),
            outbound_postage=Money.zero(),
            packaging=Money.zero(),
            net_proceeds=Money.gbp(buy_cost + profit),
            profit=Money.gbp(profit),
            roi=roi,
            margin=margin,
        )
        parsed = ParsedListing(
            name="Test Card",
            language=language,
            flags=list(flags),
            is_graded=is_graded,
            grade_company=GradeCompany.PSA if is_graded else None,
            grade_value=10.0 if is_graded else None,
        )
        card = Card(
            id="POKEMON-MEW-199/165",
            game=Game.POKEMON,
            set_code="MEW",
            set_name="151",
            number="199/165",
            name="Charizard ex",
        )
        ident = Identification(
            parsed=parsed,
            decision=Decision.MATCHED,
            match_score=0.95,
            card=card,
            condition_bucket=ConditionBucket.GRADED if is_graded else ConditionBucket.RAW_NM,
            is_graded=is_graded,
            grade_company=parsed.grade_company,
            grade_value=parsed.grade_value,
        )
        listing = ListingFacts(
            external_id="t1",
            title="Test Card",
            price=Money.gbp(buy_cost),
            category_id=category_id,
            url="https://www.ebay.co.uk/itm/t1",
        )
        return Deal(
            listing=listing,
            identification=ident,
            valuation=None,
            economics=econ,
            confidence=confidence,
            score=0.0,
        )

    return _make
