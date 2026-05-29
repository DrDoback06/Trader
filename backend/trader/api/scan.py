"""Live-scan endpoints (Phase 2).

`POST /scan` runs the configured watch list against eBay Browse (UK) when eBay
credentials are set, de-duplicates, and returns ranked deals. Without credentials
it returns a clear 400 explaining what to configure — the engine and tests still
exercise the scan path via a mocked HTTP layer.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request

from ..providers.factory import build_browse_source
from ..services.scanner import scan
from .serialize import deal_to_dict

router = APIRouter(tags=["scan"])


@router.get("/watchlist")
def get_watchlist(request: Request) -> list[dict[str, Any]]:
    return [asdict(t) for t in request.app.state.watchlist]


@router.get("/quota")
def get_quota(request: Request) -> dict[str, Any]:
    q = request.app.state.quota
    return {"daily_budget": q.daily_budget, "used": q.used, "remaining": q.remaining}


@router.post("/scan")
def run_scan(request: Request) -> dict[str, Any]:
    source = build_browse_source(request.app.state.credentials, request.app.state.settings)
    if source is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Live eBay UK scanning isn't ready. Enable the 'eBay UK — Active listings' "
                "source and add your eBay API keys under Settings → Sources."
            ),
        )

    try:
        result = scan(
            request.app.state.watchlist,
            source,
            request.app.state.catalogue,
            request.app.state.sold_provider,
            quota=request.app.state.quota,
            cfg=request.app.state.pipeline_cfg,
        )
    except httpx.HTTPStatusError as exc:
        detail = "eBay rejected the request"
        if exc.response.status_code in (401, 403):
            detail = "eBay rejected your credentials (401/403). Check your keys and EBAY_ENV."
        raise HTTPException(status_code=502, detail=detail) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach eBay: {exc}") from exc
    # Cache the freshly scanned deals so GET /deals reflects the live scan.
    request.app.state.deals = result.deals
    return {
        "targets_scanned": result.targets_scanned,
        "calls_used": result.calls_used,
        "listings_seen": result.listings_seen,
        "new_listings": result.new_listings,
        "quota_exhausted": result.quota_exhausted,
        "deals": [deal_to_dict(d) for d in result.deals],
    }
