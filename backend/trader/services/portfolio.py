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
    ident = deal.identification
    grade = ""
    if ident.is_graded and ident.grade_company is not None and ident.grade_value is not None:
        gv = int(ident.grade_value) if float(ident.grade_value).is_integer() else ident.grade_value
        grade = f"{ident.grade_company.value} {gv}"
    with session_maker() as session:
        row = PositionRow(
            card_id=card.id if card else deal.id,
            card_name=card.name if card else "(unknown)",
            number=card.number if card else "",
            set_name=card.set_name if card else "",
            grade=grade,
            condition=ident.condition_bucket.value,
            image_url=deal.listing.image_url or "",
            cost_basis=deal.economics.buy_cost.as_float,
            est_value=deal.economics.resale_gross.as_float,
            url=deal.listing.url or "",
        )
        session.add(row)
        session.commit()
        return row.id


def get_position(session_maker: sessionmaker, position_id: int) -> dict[str, Any] | None:
    with session_maker() as session:
        row = session.get(PositionRow, position_id)
        if row is None:
            return None
        return {
            "id": row.id,
            "card_name": row.card_name,
            "number": row.number,
            "set_name": row.set_name,
            "grade": row.grade,
            "condition": row.condition or "RAW_NM",
            "est_value": row.est_value,
            "status": row.status,
            "image_url": row.image_url,
        }


def mark_listed(session_maker: sessionmaker, position_id: int, listing_id: str) -> bool:
    with session_maker() as session:
        row = session.get(PositionRow, position_id)
        if row is None:
            return False
        row.status = "LISTED"
        row.listing_id = listing_id
        session.commit()
        return True


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
