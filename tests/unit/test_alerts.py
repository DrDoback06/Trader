from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from trader.core.models import Deal
from trader.db.base import init_db, make_engine, session_factory
from trader.services.alerts import dispatch_alerts


class _FakeChannel:
    name = "fake"

    def __init__(self) -> None:
        self.sent: list[str] = []

    def send(self, deal: Deal) -> None:
        self.sent.append(deal.id)


def _session_maker(tmp_path: Path):  # type: ignore[no-untyped-def]
    engine = make_engine(f"sqlite:///{tmp_path}/alerts.db")
    init_db(engine)
    return session_factory(engine)


def test_alerts_are_idempotent(tmp_path: Path, make_deal: Callable[..., Deal]) -> None:
    sm = _session_maker(tmp_path)
    channel = _FakeChannel()
    d1 = make_deal(profit=10, roi=0.5, margin=0.3, confidence=0.8)
    d1.passed_rules = True
    d1.listing.external_id = "a"
    d2 = make_deal(profit=8, roi=0.4, margin=0.3, confidence=0.8)
    d2.passed_rules = True
    d2.listing.external_id = "b"

    assert dispatch_alerts([d1, d2], channel, sm, channel_name="fake") == 2
    assert channel.sent == ["EBAY:a", "EBAY:b"]

    # Re-running sends nothing new — the same listings won't alert twice.
    assert dispatch_alerts([d1, d2], channel, sm, channel_name="fake") == 0
    assert channel.sent == ["EBAY:a", "EBAY:b"]


def test_only_passing_deals_alert(tmp_path: Path, make_deal: Callable[..., Deal]) -> None:
    sm = _session_maker(tmp_path)
    channel = _FakeChannel()
    deal = make_deal(profit=10, roi=0.5, margin=0.3, confidence=0.8)
    deal.passed_rules = False
    deal.listing.external_id = "x"
    assert dispatch_alerts([deal], channel, sm, channel_name="fake") == 0
