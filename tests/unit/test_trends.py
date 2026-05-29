from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from trader.core.models import Deal, Valuation
from trader.core.money import Money
from trader.core.rating import price_trend
from trader.db.base import init_db, make_engine, session_factory
from trader.db.models import PriceSnapshotRow
from trader.services.trends import attach_trends, record_snapshots


def _session_maker(tmp_path: Path):  # type: ignore[no-untyped-def]
    engine = make_engine(f"sqlite:///{tmp_path}/trends.db")
    init_db(engine)
    return session_factory(engine)


def _with_valuation(deal: Deal, median: float) -> Deal:
    card = deal.identification.card
    assert card is not None
    deal.valuation = Valuation(
        card_id=card.id, condition_key="RAW_NM", provider="x", median=Money.gbp(median)
    )
    return deal


def test_price_trend_pure() -> None:
    assert price_trend(120, 100) == pytest.approx(0.20)
    assert price_trend(100, None) is None
    assert price_trend(100, 0) is None


def test_attach_trends_flags_rising(tmp_path: Path, make_deal: Callable[..., Deal]) -> None:
    sm = _session_maker(tmp_path)
    deal = _with_valuation(make_deal(profit=10, roi=0.5, margin=0.3), 120)
    card_id = deal.identification.card.id  # type: ignore[union-attr]
    with sm() as session:
        session.add(
            PriceSnapshotRow(
                card_id=card_id,
                condition_key="RAW_NM",
                median=100.0,
                captured_at=datetime.now(UTC).replace(tzinfo=None) - timedelta(days=5),
            )
        )
        session.commit()

    attach_trends(sm, [deal])
    assert deal.trend_pct == pytest.approx(0.20)  # 120 vs 100 a week ago = +20%


def test_record_snapshots_writes_one_per_valued_deal(
    tmp_path: Path, make_deal: Callable[..., Deal]
) -> None:
    sm = _session_maker(tmp_path)
    deal = _with_valuation(make_deal(profit=10, roi=0.5, margin=0.3), 50)
    assert record_snapshots(sm, [deal]) == 1
    # No prior history -> no trend on a fresh card.
    fresh = _with_valuation(make_deal(profit=5, roi=0.3, margin=0.2), 50)
    fresh.identification.card = None  # unmatched -> skipped
    assert record_snapshots(sm, [fresh]) == 0
