from __future__ import annotations

from trader.core.models import Card, Game, Valuation
from trader.core.money import Money
from trader.services.valuation import CachingSoldPriceProvider

CARD = Card(id="X", game=Game.POKEMON, set_code="MEW", set_name="151", number="1/1", name="Test")


class _CountingProvider:
    name = "counting"

    def __init__(self) -> None:
        self.calls = 0

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        self.calls += 1
        return Valuation(
            card_id=card.id, condition_key=condition_key, provider=self.name, median=Money.gbp(50)
        )


def test_cache_hit_makes_no_downstream_call() -> None:
    clock = [1000.0]
    inner = _CountingProvider()
    cache = CachingSoldPriceProvider(inner, ttl_hours=1.0, clock=lambda: clock[0])

    cache.get_valuation(CARD, "RAW_NM")
    cache.get_valuation(CARD, "RAW_NM")
    assert inner.calls == 1  # second lookup served from cache

    clock[0] += 3601  # advance past the 1h TTL
    cache.get_valuation(CARD, "RAW_NM")
    assert inner.calls == 2  # expired -> refetched


def test_name_proxies_inner() -> None:
    assert CachingSoldPriceProvider(_CountingProvider()).name == "counting"
