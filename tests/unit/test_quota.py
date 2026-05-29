from __future__ import annotations

import pytest

from trader.services.quota import DailyQuota, QuotaExceeded


def test_spend_and_remaining() -> None:
    q = DailyQuota(3)
    assert q.remaining == 3
    q.spend()
    q.spend()
    assert q.used == 2
    assert q.remaining == 1


def test_can_spend() -> None:
    q = DailyQuota(1)
    assert q.can_spend(1)
    q.spend()
    assert not q.can_spend(1)


def test_exceeding_budget_raises() -> None:
    q = DailyQuota(1)
    q.spend()
    with pytest.raises(QuotaExceeded):
        q.spend()
