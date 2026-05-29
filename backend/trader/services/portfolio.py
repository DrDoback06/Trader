"""Portfolio: record what you bought, mark sales, and report P&L.

Unrealised P&L uses the market value captured at purchase (a simplification —
re-valuing live would need another sold-price call). Realised P&L is gross of
selling fees.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import sessionmaker

from ..core.models import Deal
from ..db.models import PositionRow


def buy_from_deal(session_maker: sessionmaker, deal: Deal) -> int:
    if deal.economics is None:
        raise ValueError("deal has no economics")
    card = deal.identification.card
    with session_maker() as session:
        row = PositionRow(
            card_id=card.id if card else deal.id,
            card_name=card.name if card else "(unknown)",
            cost_basis=deal.economics.buy_cost.as_float,
            est_value=deal.economics.resale_gross.as_float,
            url=deal.listing.url or "",
        )
        session.add(row)
        session.commit()
        return row.id


def mark_sold(session_maker: sessionmaker, position_id: int, price: float) -> bool:
    with session_maker() as session:
        row = session.get(PositionRow, position_id)
        if row is None:
            return False
        row.status = "SOLD"
        row.sold_price = price
        row.sold_at = datetime.now(UTC).replace(tzinfo=None)
        session.commit()
        return True


def portfolio_summary(session_maker: sessionmaker) -> dict[str, Any]:
    with session_maker() as session:
        rows = session.scalars(
            select(PositionRow).order_by(PositionRow.acquired_at.desc())
        ).all()

    positions: list[dict[str, Any]] = []
    invested = unrealised = realised = 0.0
    held = 0
    for r in rows:
        positions.append(
            {
                "id": r.id,
                "card": r.card_name,
                "cost_basis": round(r.cost_basis, 2),
                "est_value": round(r.est_value, 2),
                "status": r.status,
                "sold_price": r.sold_price,
                "url": r.url,
            }
        )
        if r.status == "HELD":
            held += 1
            invested += r.cost_basis
            unrealised += r.est_value - r.cost_basis
        else:
            realised += (r.sold_price or 0.0) - r.cost_basis

    return {
        "positions": positions,
        "held": held,
        "invested": round(invested, 2),
        "unrealised_pnl": round(unrealised, 2),
        "realised_pnl": round(realised, 2),
    }
