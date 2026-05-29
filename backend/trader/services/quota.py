"""Daily API-call budget tracker (keeps us under eBay's ~5,000/day app quota)."""

from __future__ import annotations

from datetime import UTC, datetime


class QuotaExceeded(RuntimeError):
    pass


class DailyQuota:
    def __init__(self, daily_budget: int) -> None:
        self.daily_budget = daily_budget
        self._date = self._today()
        self._used = 0

    @staticmethod
    def _today() -> str:
        return datetime.now(UTC).date().isoformat()

    def _roll_if_new_day(self) -> None:
        today = self._today()
        if today != self._date:
            self._date = today
            self._used = 0

    @property
    def used(self) -> int:
        self._roll_if_new_day()
        return self._used

    @property
    def remaining(self) -> int:
        self._roll_if_new_day()
        return max(0, self.daily_budget - self._used)

    def can_spend(self, n: int = 1) -> bool:
        return self.remaining >= n

    def spend(self, n: int = 1) -> int:
        self._roll_if_new_day()
        if self._used + n > self.daily_budget:
            raise QuotaExceeded(
                f"daily call budget {self.daily_budget} exhausted ({self._used} used)"
            )
        self._used += n
        return self._used
