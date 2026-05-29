"""Live eBay-UK sold-price provider via a RapidAPI service.

Implements ``SoldPriceProvider`` against the ``ebay-average-selling-price``
``findCompletedItems`` endpoint with ``site_id=3`` (eBay UK / GBP). Swappable —
the engine only sees the interface, so this can be replaced by eBay's official
Marketplace Insights API later if access is granted.
"""

from __future__ import annotations

from typing import Any

import httpx

from ..core.models import Card, Valuation
from ..core.money import Money


class RapidApiSoldPriceProvider:
    name = "ebay_uk_sold"

    def __init__(
        self,
        api_key: str,
        *,
        host: str = "ebay-average-selling-price.p.rapidapi.com",
        site_id: str = "3",
        max_results: int = 120,
        remove_outliers: bool = True,
        client: httpx.Client | None = None,
    ) -> None:
        self._key = api_key
        self._host = host
        self._site_id = site_id
        self._max_results = max_results
        self._remove_outliers = remove_outliers
        self._client = client or httpx.Client(timeout=25.0)

    def _query(self, card: Card, condition_key: str) -> str:
        parts = [card.name, card.number]
        if card.set_name:
            parts.append(card.set_name)
        if condition_key.startswith("GRADED_"):
            # e.g. GRADED_PSA_10 -> add "PSA 10" to the search
            _, company, grade = condition_key.split("_", 2)
            parts.extend([company, grade])
        return " ".join(p for p in parts if p)

    @staticmethod
    def _money(value: Any) -> Money | None:
        if value in (None, "", 0, "0"):
            return None
        try:
            return Money.gbp(str(value))
        except Exception:  # pragma: no cover - defensive against odd payloads
            return None

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        body = {
            "keywords": self._query(card, condition_key),
            "site_id": self._site_id,
            "max_search_results": str(self._max_results),
            "remove_outliers": self._remove_outliers,
            "excluded_keywords": "proxy fake repro reprint lot joblot bundle",
        }
        resp = self._client.post(
            f"https://{self._host}/findCompletedItems",
            headers={
                "x-rapidapi-key": self._key,
                "x-rapidapi-host": self._host,
                "content-type": "application/json",
            },
            json=body,
        )
        resp.raise_for_status()
        data = resp.json()

        median = self._money(data.get("median_price")) or self._money(data.get("average_price"))
        if median is None or median.amount <= 0:
            return None

        low = self._money(data.get("min_price"))
        high = self._money(data.get("max_price"))
        sample = int(data.get("total_results") or len(data.get("products") or []) or 0)
        spread = 0.0
        if low is not None and high is not None and median.amount > 0:
            spread = float((high.amount - low.amount) / median.amount)

        return Valuation(
            card_id=card.id,
            condition_key=condition_key,
            provider=self.name,
            median=median,
            average=self._money(data.get("average_price")),
            low=low,
            high=high,
            sample_size=sample,
            spread=spread,
            currency="GBP",
        )
