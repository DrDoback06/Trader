from __future__ import annotations

from trader.core.models import ListingFacts
from trader.core.money import Money
from trader.services.dedup import Dedup


def _listing(
    external_id: str = "1", title: str = "Charizard ex 199/165", price: float = 45.0
) -> ListingFacts:
    return ListingFacts(
        external_id=external_id, title=title, price=Money.gbp(price), seller="cardshop"
    )


def test_same_id_is_not_new_twice() -> None:
    d = Dedup()
    listing = _listing()
    assert d.is_new(listing) is True
    assert d.is_new(listing) is False


def test_relist_under_new_id_caught_by_fingerprint() -> None:
    d = Dedup()
    assert d.is_new(_listing(external_id="1")) is True
    assert d.is_new(_listing(external_id="2")) is False  # same title/seller/price


def test_different_price_is_treated_as_new() -> None:
    d = Dedup()
    assert d.is_new(_listing(external_id="1", price=45.0)) is True
    assert d.is_new(_listing(external_id="2", price=40.0)) is True
