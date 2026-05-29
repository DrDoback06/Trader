"""Cache-first wrapper around any ``SoldPriceProvider``.

Sold-price lookups cost money/quota, so we cache each ``(card, condition)`` result
(including misses) for a TTL. A cache hit makes zero downstream calls.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass

from ..core.models import Card, Valuation
from ..providers.base import SoldPriceProvider


@dataclass
class _Entry:
    valuation: Valuation | None
    expires_at: float


class CachingSoldPriceProvider:
    def __init__(
        self,
        inner: SoldPriceProvider,
        *,
        ttl_hours: float = 72.0,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._inner = inner
        self._ttl = ttl_hours * 3600.0
        self._clock = clock
        self._cache: dict[tuple[str, str], _Entry] = {}
        self.name = inner.name

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        key = (card.id, condition_key)
        now = self._clock()
        entry = self._cache.get(key)
        if entry is not None and now < entry.expires_at:
            return entry.valuation
        valuation = self._inner.get_valuation(card, condition_key)
        self._cache[key] = _Entry(valuation, now + self._ttl)
        return valuation
