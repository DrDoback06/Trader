"""Alerts API — recent alert history and a one-tap test alert."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from sqlalchemy import desc, select

from ..db.models import AlertRow
from ..providers.factory import build_alert_channel

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("")
def list_alerts(request: Request) -> list[dict[str, Any]]:
    with request.app.state.session_maker() as session:
        rows = session.scalars(
            select(AlertRow).order_by(desc(AlertRow.created_at)).limit(50)
        ).all()
        return [
            {
                "channel": r.channel,
                "deal_id": r.deal_id,
                "card": r.card,
                "profit": r.profit,
                "created_at": r.created_at.isoformat(),
            }
            for r in rows
        ]


@router.post("/test")
def test_alert(request: Request) -> dict[str, Any]:
    """Send the current top passing deal via the configured channel, to verify setup."""
    passing = [d for d in request.app.state.deals if d.passed_rules]
    if not passing:
        raise HTTPException(status_code=400, detail="no passing deal to send a test alert for")
    channel = build_alert_channel(request.app.state.settings)
    try:
        channel.send(passing[0])
    except Exception as exc:  # noqa: BLE001 - surface any channel error to the caller
        raise HTTPException(status_code=502, detail=f"alert channel error: {exc}") from exc
    return {"sent": True, "channel": channel.name, "deal_id": passing[0].id}
