"""Alerts API — history, a test alert, and auto-scan scheduling."""

from __future__ import annotations

import contextlib
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import desc, select

from ..db.models import AlertRow
from ..providers.factory import build_alert_channel
from ..services.scheduler import start_scheduler

router = APIRouter(prefix="/alerts", tags=["alerts"])


class ScheduleIn(BaseModel):
    interval_min: int = 0


def _status(request: Request) -> dict[str, Any]:
    settings = request.app.state.settings
    channel = build_alert_channel(request.app.state.credentials, settings)
    sched = getattr(request.app.state, "scheduler", None)
    return {
        "interval_min": settings.scan_interval_min,
        "channel": channel.name,
        "running": bool(sched is not None and getattr(sched, "running", False)),
    }


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


@router.get("/status")
def alerts_status(request: Request) -> dict[str, Any]:
    return _status(request)


@router.post("/test")
def test_alert(request: Request) -> dict[str, Any]:
    """Send the current top passing deal via the configured channel, to verify setup."""
    passing = [d for d in request.app.state.deals if d.passed_rules]
    if not passing:
        raise HTTPException(status_code=400, detail="no passing deal to send a test alert for")
    channel = build_alert_channel(request.app.state.credentials, request.app.state.settings)
    try:
        channel.send(passing[0])
    except Exception as exc:  # noqa: BLE001 - surface any channel error to the caller
        raise HTTPException(status_code=502, detail=f"alert channel error: {exc}") from exc
    return {"sent": True, "channel": channel.name, "deal_id": passing[0].id}


@router.post("/schedule")
def set_schedule(request: Request, body: ScheduleIn) -> dict[str, Any]:
    """Start, stop, or reconfigure the auto-scan. interval_min=0 turns it off."""
    app = request.app
    sched = getattr(app.state, "scheduler", None)
    if sched is not None:
        with contextlib.suppress(Exception):  # best-effort stop of the old job
            sched.shutdown(wait=False)
    app.state.settings.scan_interval_min = max(0, body.interval_min)
    app.state.scheduler = start_scheduler(app)
    return _status(request)
