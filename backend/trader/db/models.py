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


class PositionRow(Base):
    """A card you've bought (or sold) — for portfolio P&L tracking."""

    __tablename__ = "positions"

    id: Mapped[int] = mapped_column(primary_key=True)
    card_id: Mapped[str] = mapped_column(String(128), index=True)
    card_name: Mapped[str] = mapped_column(String(256), default="")
    number: Mapped[str] = mapped_column(String(32), default="")
    set_name: Mapped[str] = mapped_column(String(128), default="")
    grade: Mapped[str] = mapped_column(String(32), default="")  # e.g. "PSA 9", "" if raw
    condition: Mapped[str] = mapped_column(String(16), default="")  # RAW_NM, GRADED, ...
    image_url: Mapped[str] = mapped_column(String(512), default="")
    cost_basis: Mapped[float] = mapped_column(Float)  # what you paid (buy cost)
    est_value: Mapped[float] = mapped_column(Float)  # market value at purchase
    status: Mapped[str] = mapped_column(String(16), default="HELD")  # HELD | SOLD | LISTED
    sold_price: Mapped[float | None] = mapped_column(Float, default=None)
    listing_id: Mapped[str] = mapped_column(String(64), default="")  # eBay listing id once relisted
    url: Mapped[str] = mapped_column(String(512), default="")
    acquired_at: Mapped[datetime] = mapped_column(default=_utcnow)
    sold_at: Mapped[datetime | None] = mapped_column(default=None)
