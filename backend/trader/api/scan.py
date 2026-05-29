"""Live-scan endpoints (Phase 2).

`POST /scan` runs the configured watch list against eBay Browse (UK) when eBay
credentials are set, de-duplicates, and returns ranked deals. Without credentials
it returns a clear 400 explaining what to configure — the engine and tests still
exercise the scan path via a mocked HTTP layer.
"""

from __future__ import annotations

from dataclasses import asdict, replace
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..core.models import ListingFacts, WatchTarget
from ..core.money import Money
from ..core.rules import RuleSet
from ..providers.factory import build_browse_source
from ..services.pipeline import evaluate_listing
from ..services.scanner import scan
from ..services.trends import attach_trends, record_snapshots
from ..services.watchlist import (
    cheapest_sweep_target,
    ending_soon_sweep_target,
    graded_sweep_targets,
    hidden_gem_targets,
    sealed_sweep_targets,
)
from .serialize import deal_to_dict

router = APIRouter(tags=["scan"])


class ScanRequest(BaseModel):
    # watchlist | cheapest | ending_soon | everything
    mode: str = "watchlist"
    ending_within_hours: int = 12
    max_price: float | None = None


def _targets_for(request: Request, body: ScanRequest) -> list[WatchTarget]:
    watchlist = list(request.app.state.watchlist)
    cheapest = cheapest_sweep_target(max_price=body.max_price)
    ending = ending_soon_sweep_target(
        ending_within_hours=body.ending_within_hours, max_price=body.max_price
    )
    return {
        "watchlist": watchlist,
        "cheapest": [cheapest],
        "ending_soon": [ending],
        "hidden_gems": hidden_gem_targets(max_price=body.max_price),
        "graded": graded_sweep_targets(max_price=body.max_price),
        "sealed": sealed_sweep_targets(max_price=body.max_price),
        "everything": [*watchlist, cheapest, ending],
    }.get(body.mode, watchlist)


@router.get("/watchlist")
def get_watchlist(request: Request) -> list[dict[str, Any]]:
    return [asdict(t) for t in request.app.state.watchlist]


@router.get("/quota")
def get_quota(request: Request) -> dict[str, Any]:
    q = request.app.state.quota
    return {"daily_budget": q.daily_budget, "used": q.used, "remaining": q.remaining}


@router.post("/scan")
def run_scan(request: Request, body: ScanRequest | None = None) -> dict[str, Any]:
    body = body or ScanRequest()
    source = build_browse_source(request.app.state.credentials, request.app.state.settings)
    if source is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Live eBay UK scanning isn't ready. Enable the 'eBay UK — Active listings' "
                "source and add your eBay API keys under Settings → Sources."
            ),
        )

    cfg = request.app.state.pipeline_cfg
    if body.mode == "sealed":
        cfg = replace(cfg, catalogue_free=True)  # value sealed product by title
    elif body.mode == "graded":
        cfg = replace(cfg, rules=RuleSet.for_holds())  # surface holds across all grades

    try:
        result = scan(
            _targets_for(request, body),
            source,
            request.app.state.catalogue,
            request.app.state.sold_provider,
            quota=request.app.state.quota,
            cfg=cfg,
        )
    except httpx.HTTPStatusError as exc:
        detail = "eBay rejected the request"
        if exc.response.status_code in (401, 403):
            detail = "eBay rejected your credentials (401/403). Check your keys and EBAY_ENV."
        raise HTTPException(status_code=502, detail=detail) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach eBay: {exc}") from exc

    # Momentum: compare to prior history, then record today's sample.
    attach_trends(request.app.state.session_maker, result.deals)
    record_snapshots(request.app.state.session_maker, result.deals)
    # Cache the freshly scanned deals so GET /deals reflects the live scan.
    request.app.state.deals = result.deals
    return {
        "mode": body.mode,
        "targets_scanned": result.targets_scanned,
        "calls_used": result.calls_used,
        "listings_seen": result.listings_seen,
        "new_listings": result.new_listings,
        "quota_exhausted": result.quota_exhausted,
        "deals": [deal_to_dict(d) for d in result.deals],
    }


class EvaluateIn(BaseModel):
    query: str
    ask_price: float
    shipping: float | None = None


@router.post("/evaluate")
def evaluate_card(request: Request, body: EvaluateIn) -> dict[str, Any]:
    """Evaluate one card you supply (name + the price you'd pay) against real UK
    sold prices. This is the live engine minus the auto-discovery that needs eBay
    keys, so it works today with just the RapidAPI sold-price key."""
    query = body.query.strip()
    if len(query) < 3:
        raise HTTPException(status_code=400, detail="Type a card name to check.")
    if body.ask_price <= 0:
        raise HTTPException(status_code=400, detail="Enter the price you'd pay (greater than 0).")

    # catalogue_free: value any typed-in title directly, even when it isn't in the
    # bundled catalogue (the full ~20k-card catalogue is an optional local import).
    cfg = replace(request.app.state.pipeline_cfg, catalogue_free=True)
    listing = ListingFacts(
        external_id=f"check:{query.lower()}",
        title=query,
        price=Money.gbp(round(body.ask_price, 2)),
        shipping=Money.gbp(round(body.shipping, 2)) if body.shipping else None,
    )
    try:
        deal = evaluate_listing(
            listing,
            request.app.state.catalogue,
            request.app.state.sold_provider,
            cfg,
        )
    except httpx.HTTPStatusError as exc:
        detail = f"Sold-price lookup failed ({exc.response.status_code})."
        if exc.response.status_code in (401, 403):
            detail = (
                "Your RapidAPI key was rejected (401/403). Check the key and that you've "
                "subscribed to the eBay Average Selling Price API."
            )
        raise HTTPException(status_code=502, detail=detail) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail=f"Couldn't reach the sold-price service: {exc}"
        ) from exc

    return deal_to_dict(deal)
