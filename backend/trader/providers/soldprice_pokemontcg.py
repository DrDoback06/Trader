"""Free market-price provider via pokemontcg.io.

A no-key (the same public API the catalogue importer already uses) ``SoldPriceProvider``
that returns a *reference market value* per card from Cardmarket (EUR) or, failing that,
TCGplayer (USD), converted to GBP. It is a quick "is this underpriced?" indicator — not
real eBay-UK *sold* medians — so the app works for free, and the optional RapidAPI
sold-price source can still be switched on for exact UK valuations.

Notes / honest limits:
* Prices are an ungraded single's market reference. Graded buckets (``GRADED_*``) return
  ``None`` — grade those with the eBay-sold source. A rough condition ladder discounts
  played raw cards so an LP/MP listing isn't valued at NM market.
* FX rates are approximate and configurable (a quick indicator, not an FX desk).
* Free tier is rate-limited, so calls are spaced and 429s are retried; every result is
  cached by the wrapping :class:`CachingSoldPriceProvider`, so this fires at most once
  per (card, condition) per TTL.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

import httpx

from ..core.models import Card, Valuation
from ..core.money import Money

# Rough TCG condition ladder applied to the (NM) market reference, so a played raw card
# isn't valued as Near Mint. Deliberately conservative — biases toward NOT flagging a
# played card as a steal.
_CONDITION_MULTIPLIER: dict[str, float] = {
    "RAW_NM": 1.0,
    "RAW_LP": 0.85,
    "RAW_MP": 0.70,
    "RAW_HP": 0.55,
    "RAW_DAMAGED": 0.40,
}

# A market reference isn't a basket of real sold comps, so we don't let confidence max
# out on it: a moderate effective sample + a baseline spread keep the verdict honest
# (a genuine discount still clears the rules; a marginal one doesn't).
_REFERENCE_SAMPLE_SIZE = 6
_BASELINE_SPREAD = 0.30


def _first_number(number: str) -> str:
    """'199/165' -> '199'; promos like 'SWSH001' pass through unchanged."""
    return number.split("/", 1)[0].strip()


class PokemonTcgPriceProvider:
    name = "pokemontcg_market"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str = "https://api.pokemontcg.io/v2/cards",
        eur_gbp: float = 0.85,
        usd_gbp: float = 0.79,
        client: httpx.Client | None = None,
        min_interval: float = 0.3,
        max_retries: int = 3,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._key = api_key or None
        self._base = base_url
        self._eur_gbp = eur_gbp
        self._usd_gbp = usd_gbp
        self._client = client or httpx.Client(timeout=20.0)
        self._min_interval = min_interval
        self._max_retries = max_retries
        self._sleep = sleep
        self._clock = clock
        self._last_call = 0.0

    # --- HTTP (throttled + 429-aware, like the RapidAPI provider) ----------------

    def _throttle(self) -> None:
        if self._min_interval <= 0:
            return
        wait = self._min_interval - (self._clock() - self._last_call)
        if wait > 0:
            self._sleep(wait)

    def _get(self, params: dict[str, Any]) -> httpx.Response:
        headers = {"X-Api-Key": self._key} if self._key else {}
        attempt = 0
        while True:
            self._throttle()
            resp = self._client.get(self._base, params=params, headers=headers)
            self._last_call = self._clock()
            if resp.status_code == 429 and attempt < self._max_retries:
                attempt += 1
                retry_after = resp.headers.get("Retry-After")
                try:
                    wait = float(retry_after) if retry_after else 0.0
                except ValueError:
                    wait = 0.0
                self._sleep(wait or min(self._min_interval * 2**attempt, 8.0))
                continue
            return resp

    # --- price extraction --------------------------------------------------------

    def _best_match(self, card: Card) -> dict[str, Any] | None:
        q = f'name:"{card.name}"'
        num = _first_number(card.number)
        if num:
            q += f' number:"{num}"'
        resp = self._get(
            {"q": q, "select": "id,name,number,set,cardmarket,tcgplayer", "pageSize": 12}
        )
        resp.raise_for_status()
        data = resp.json().get("data") or []
        return data[0] if data else None

    def _reference_gbp(self, match: dict[str, Any]) -> tuple[Money | None, Money | None]:
        """(market, low) in GBP from Cardmarket (preferred) or TCGplayer."""
        cm = (match.get("cardmarket") or {}).get("prices") or {}
        eur = cm.get("trendPrice") or cm.get("averageSellPrice") or cm.get("avg7")
        if eur:
            market = Money.of(str(eur), "EUR").convert(self._eur_gbp, "GBP")
            low_eur = cm.get("lowPrice") or cm.get("avg1")
            low = Money.of(str(low_eur), "EUR").convert(self._eur_gbp, "GBP") if low_eur else None
            return market.quantize(), (low.quantize() if low else None)

        # Fall back to TCGplayer (USD): take the first finish that has a market/mid price.
        tcg = (match.get("tcgplayer") or {}).get("prices") or {}
        for finish in tcg.values():
            if not isinstance(finish, dict):
                continue
            usd = finish.get("market") or finish.get("mid")
            if usd:
                market = Money.of(str(usd), "USD").convert(self._usd_gbp, "GBP")
                low_usd = finish.get("low")
                low = (
                    Money.of(str(low_usd), "USD").convert(self._usd_gbp, "GBP")
                    if low_usd
                    else None
                )
                return market.quantize(), (low.quantize() if low else None)
        return None, None

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        # Reference prices are for ungraded singles — graded slabs need real sold comps.
        if condition_key.startswith("GRADED_"):
            return None
        multiplier = _CONDITION_MULTIPLIER.get(condition_key, 1.0)

        match = self._best_match(card)
        if match is None:
            return None
        market, low = self._reference_gbp(match)
        if market is None or market.amount <= 0:
            return None

        median = market.convert(multiplier, "GBP").quantize() if multiplier != 1.0 else market
        low_adj = low.convert(multiplier, "GBP").quantize() if (low and multiplier != 1.0) else low
        spread = _BASELINE_SPREAD
        if low_adj is not None and median.amount > 0:
            spread = max(_BASELINE_SPREAD, float((median.amount - low_adj.amount) / median.amount))

        return Valuation(
            card_id=card.id,
            condition_key=condition_key,
            provider=self.name,
            median=median,
            average=median,
            low=low_adj,
            high=None,
            sample_size=_REFERENCE_SAMPLE_SIZE,
            spread=round(spread, 3),
            currency="GBP",
        )
