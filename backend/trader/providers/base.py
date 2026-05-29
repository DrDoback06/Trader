"""Provider interfaces (Protocols). Concrete implementations live alongside."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Protocol, runtime_checkable

from ..core.models import Card, Deal, ListingFacts, Valuation


@runtime_checkable
class ListingSource(Protocol):
    """A source of active listings to evaluate (e.g. eBay Browse — Phase 2)."""

    def fetch(self, *, query: str, limit: int = 50) -> Sequence[ListingFacts]: ...


@runtime_checkable
class SoldPriceProvider(Protocol):
    """A source of sold-price valuations (e.g. eBay UK sold data — Phase 3)."""

    name: str

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None: ...


@runtime_checkable
class AlertChannel(Protocol):
    """A way to notify the user of a deal (console, Telegram — Phase 4)."""

    def send(self, deal: Deal) -> None: ...


@runtime_checkable
class BuyExecutor(Protocol):
    """Seam for a future buy step. Intentionally not implemented (see buy_noop)."""

    def buy(self, listing: ListingFacts) -> None: ...
