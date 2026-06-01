"""Try several sold-price providers in order, first hit wins.

Lets the app prefer an accurate-but-limited source (eBay-UK sold via RapidAPI) while
falling back to a free always-on one (pokemontcg.io market price), so a valuation —
and therefore an ROI/profit verdict — comes back even when the premium source returns
nothing or is rate-limited / out of quota. A provider that raises a transient HTTP error
is skipped rather than allowed to kill the whole lookup; if *every* provider errors, the
last error propagates (so the caller can still surface "valuation unavailable").
"""

from __future__ import annotations

import httpx

from ..core.models import Card, Valuation
from ..providers.base import SoldPriceProvider


class ChainSoldPriceProvider:
    def __init__(self, providers: list[SoldPriceProvider], *, name: str = "chain") -> None:
        if not providers:
            raise ValueError("ChainSoldPriceProvider needs at least one provider")
        self._providers = providers
        self.name = name

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        last_error: httpx.HTTPError | None = None
        for provider in self._providers:
            try:
                valuation = provider.get_valuation(card, condition_key)
            except httpx.HTTPError as exc:
                last_error = exc  # this source is down/limited — try the next one
                continue
            if valuation is not None:
                return valuation
        if last_error is not None:
            raise last_error
        return None
