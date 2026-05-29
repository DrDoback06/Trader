"""Health / status endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Request

router = APIRouter(tags=["health"])


@router.get("/health")
def health(request: Request) -> dict[str, object]:
    deals = request.app.state.deals
    return {
        "status": "ok",
        "deals_evaluated": len(deals),
        "deals_passing": sum(1 for d in deals if d.passed_rules),
    }
