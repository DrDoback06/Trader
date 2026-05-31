"""Live-scan endpoints (Phase 2).

`POST /scan` runs the configured watch list against eBay Browse (UK) when eBay
credentials are set, de-duplicates, and returns ranked deals. `POST /search` runs
one typed card search and values every live listing against that card. Without
credentials they return a clear 400 explaining what to configure — the engine and
tests still exercise the scan path via a mocked HTTP layer.
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
from ..services.pipeline import evaluate_listing, resolve_searched_card
from ..services.scanner import scan, search_card
from ..services.trends import attach_trends, record_snapshots
from ..services.watchlist import (
    POKEMON_SINGLES_GB,
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
    max_valuations: int | None = None  # cap live valuations this scan (else server default)


class SearchRequest(BaseModel):
    query: str
    max_price: float | None = None
    pages: int = 1


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


def _ebay_http_error(exc: httpx.HTTPStatusError, credentials: Any) -> HTTPException:
    """Translate an eBay HTTP error into a user-actionable 502, calling out the
    common sandbox-vs-production key mix-up on a 401/403."""
    detail = "eBay rejected the request"
    if exc.response.status_code in (401, 403):
        client_id = credentials.get("ebay_client_id") or ""
        if "SBX" in client_id.upper():
            detail = (
                "You're using your eBay SANDBOX keys (App ID contains 'SBX'), but live "
                "scanning uses Production. Paste your PRODUCTION App ID + Cert ID (they "
                "contain 'PRD') under Sources & Keys."
            )
        else:
            detail = (
                "eBay rejected your credentials (401/403). Check your Production App ID + "
                "Cert ID are correct and the keyset is enabled."
            )
    return HTTPException(status_code=502, detail=detail)


def _require_browse_source(request: Request) -> Any:
    source = build_browse_source(request.app.state.credentials, request.app.state.settings)
    if source is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Live eBay UK scanning isn't ready. Enable the 'eBay UK — Active listings' "
                "source and add your eBay API keys under Settings → Sources."
            ),
        )
    return source


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
    source = _require_browse_source(request)

    # Value a listing by its title even when it doesn't match the catalogue (flagged
    # UNVERIFIED), so a scan still finds deals before the full catalogue is imported.
    cfg = replace(request.app.state.pipeline_cfg, catalogue_free=True)
    if body.mode == "graded":
        cfg = replace(cfg, rules=RuleSet.for_holds())  # surface holds across all grades

    try:
        result = scan(
            _targets_for(request, body),
            source,
            request.app.state.catalogue,
            request.app.state.sold_provider,
            quota=request.app.state.quota,
            cfg=cfg,
            max_valuations=(
                body.max_valuations
                if body.max_valuations is not None
                else request.app.state.settings.max_valuations_per_scan
            ),
        )
    except httpx.HTTPStatusError as exc:
        raise _ebay_http_error(exc, request.app.state.credentials) from exc
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
        "valued": result.valued,
        "unvalued": result.unvalued,
        "quota_exhausted": result.quota_exhausted,
        "deals": [deal_to_dict(d) for d in result.deals],
    }


@router.post("/search")
def search_listings(request: Request, body: SearchRequest) -> dict[str, Any]:
    """Card search: fetch live UK listings for one typed card and value them all
    against that card (clean identity). Results are returned directly — they're the
    hero list and are kept separate from the category-sweep deals in `/deals`."""
    query = body.query.strip()
    if len(query) < 3:
        raise HTTPException(status_code=400, detail="Type a card name (and number) to search.")
    source = _require_browse_source(request)

    # Pinned identity — we value against the searched card, so no catalogue_free.
    cfg = request.app.state.pipeline_cfg
    card = resolve_searched_card(query, request.app.state.catalogue, cfg)

    try:
        result = search_card(
            query,
            card,
            source,
            request.app.state.sold_provider,
            quota=request.app.state.quota,
            cfg=cfg,
            max_price=body.max_price,
            pages=max(1, min(body.pages, 3)),
            category_ids=(POKEMON_SINGLES_GB,),
        )
    except httpx.HTTPStatusError as exc:
        raise _ebay_http_error(exc, request.app.state.credentials) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach eBay: {exc}") from exc

    attach_trends(request.app.state.session_maker, result.deals)
    # Make search results addable to the portfolio via '📌 Bought' (like 'Check a card').
    evals = getattr(request.app.state, "recent_evals", None)
    if evals is not None:
        if len(evals) > 200:
            evals.clear()
        for d in result.deals:
            evals[d.listing.external_id] = d

    return {
        "query": query,
        "card": {
            "id": card.id,
            "name": card.name,
            "number": card.number,
            "set_name": card.set_name,
            "set_code": card.set_code,
        },
        "listings_seen": result.listings_seen,
        "matched": len(result.deals),
        "valued": result.valued,
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

    # Remember it so '📌 Bought' can add this checked card to the portfolio.
    evals = getattr(request.app.state, "recent_evals", None)
    if evals is not None:
        if len(evals) > 100:
            evals.clear()
        evals[listing.external_id] = deal

    return deal_to_dict(deal)
