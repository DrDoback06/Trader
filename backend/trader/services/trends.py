"""Price-history snapshots and momentum.

Each scan records the current market value per card, building a history. On later
scans we compare today's value to the oldest sample in a window to flag rising
(buy before it climbs) and falling cards.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import sessionmaker

from ..core.models import Deal
from ..core.rating import price_trend
from ..db.models import PriceSnapshotRow


def record_snapshots(session_maker: sessionmaker, deals: list[Deal]) -> int:
    """Persist the current median per (card, condition). Returns rows written."""
    written = 0
    with session_maker() as session:
        for deal in deals:
            card = deal.identification.card
            if deal.valuation is None or card is None:
                continue
            session.add(
                PriceSnapshotRow(
                    card_id=card.id,
                    condition_key=deal.valuation.condition_key,
                    median=deal.valuation.median.as_float,
                )
            )
            written += 1
        session.commit()
    return written


def attach_trends(session_maker: sessionmaker, deals: list[Deal], *, window_days: int = 30) -> None:
    """Set ``deal.trend_pct`` from the oldest snapshot within ``window_days``.

    Call this BEFORE :func:`record_snapshots` so it compares today's value to
    prior history, not the sample we're about to write.
    """
    cutoff = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=window_days)
    with session_maker() as session:
        for deal in deals:
            card = deal.identification.card
            if deal.valuation is None or card is None:
                continue
            earliest = session.scalars(
                select(PriceSnapshotRow)
                .where(
                    PriceSnapshotRow.card_id == card.id,
                    PriceSnapshotRow.condition_key == deal.valuation.condition_key,
                    PriceSnapshotRow.captured_at >= cutoff,
                )
                .order_by(PriceSnapshotRow.captured_at.asc())
            ).first()
            if earliest is not None:
                deal.trend_pct = price_trend(deal.valuation.median.as_float, earliest.median)
