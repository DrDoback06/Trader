"""ORM tables. Phase 4 starts with the alert-dedup table; price snapshots and
positions land here in later phases."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import Float, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


def _utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class AlertRow(Base):
    __tablename__ = "alerts"
    __table_args__ = (UniqueConstraint("channel", "dedup_key", name="uq_channel_dedup"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    channel: Mapped[str] = mapped_column(String(32))
    dedup_key: Mapped[str] = mapped_column(String(128))
    deal_id: Mapped[str] = mapped_column(String(128))
    card: Mapped[str] = mapped_column(String(256), default="")
    profit: Mapped[float] = mapped_column(Float, default=0.0)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)


class PriceSnapshotRow(Base):
    """A market-value sample over time, used to compute price trend / momentum."""

    __tablename__ = "price_snapshots"

    id: Mapped[int] = mapped_column(primary_key=True)
    card_id: Mapped[str] = mapped_column(String(128), index=True)
    condition_key: Mapped[str] = mapped_column(String(32))
    median: Mapped[float] = mapped_column(Float)
    captured_at: Mapped[datetime] = mapped_column(default=_utcnow, index=True)
