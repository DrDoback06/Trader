"""Offline sold-price provider backed by a JSON fixture.

Lets the entire pipeline run with no network and no API keys (Phase 1), and backs
the unit/e2e tests. Implements the same :class:`SoldPriceProvider` interface as
the live provider added in Phase 3.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ..core.models import Card, Valuation
from ..core.money import Money


class FixtureSoldPriceProvider:
    name = "fixture"

    def __init__(self, data: dict[str, dict[str, Any]]) -> None:
        self.data = data

    @classmethod
    def from_file(cls, path: str | Path) -> FixtureSoldPriceProvider:
        return cls(json.loads(Path(path).read_text(encoding="utf-8")))

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        rec = self.data.get(f"{card.id}|{condition_key}")
        if rec is None:
            return None
        median = Money.gbp(rec["median"])
        low = Money.gbp(rec["low"]) if "low" in rec else None
        high = Money.gbp(rec["high"]) if "high" in rec else None
        spread = 0.0
        if low is not None and high is not None and median.amount > 0:
            spread = float((high.amount - low.amount) / median.amount)
        return Valuation(
            card_id=card.id,
            condition_key=condition_key,
            provider=self.name,
            median=median,
            average=Money.gbp(rec["average"]) if "average" in rec else None,
            low=low,
            high=high,
            sample_size=int(rec.get("sample_size", 0)),
            spread=spread,
            currency="GBP",
        )
