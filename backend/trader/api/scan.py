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

from ..core.models import Card, ListingFacts, WatchTarget
from ..core.money import Money
from ..core.rules import RuleSet
from ..providers.factory import build_browse_source
from ..services.pipeline import PipelineConfig, evaluate_listing, resolve_searched_card
from ..services.scanner import scan
from ..services.trends import attach_trends, record_snapshots
from ..services.typos import misspellings
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
    max_valuations: int | None = None  # cap live valuations this scan (else server default)


def _scan_error_detail(request: Request, errors: list[str]) -> str:
    """A human message for a scan where every eBay target failed, leading with eBay's
    own error text and adding a sandbox-keys hint when the App ID looks like SBX."""
    client_id = request.app.state.credentials.get("ebay_client_id") or ""
    parts: list[str] = []
    if "SBX" in client_id.upper():
        parts.append(
            "These look like SANDBOX keys (App ID contains 'SBX') — live scanning uses "
            "Production, so paste your PRODUCTION App ID + Cert ID (they contain 'PRD')."
        )
    unique = list(dict.fromkeys(errors))[:4]
    parts.append("eBay rejected every scan target — " + " · ".join(unique))
    return " ".join(parts)


def _basic_keyset_target(target: WatchTarget) -> WatchTarget:
    """Make a target runnable on a standard eBay keyset: pure keyword searches work, but
    whole-category browsing needs Buy API full access. Drop the category filter from
    keyword targets; leave category-only sweeps untouched (they can't run without it, and
    will surface eBay's real 'needs full access' error if the user runs that mode)."""
    return replace(target, category_ids=()) if target.query else target


def _targets_for(request: Request, body: ScanRequest) -> list[WatchTarget]:
    full = request.app.state.settings.ebay_buy_api_full_access
    max_price = body.max_price
    watchlist = list(request.app.state.watchlist)
    cheapest = cheapest_sweep_target(max_price=max_price)
    ending = ending_soon_sweep_target(
        ending_within_hours=body.ending_within_hours, max_price=max_price
    )

    # "Everything" scours the marketplace. With Buy API full access that's whole-category
    # sweeps; on a standard keyset we fan out across many *keyword* searches instead (card
    # names, sealed product, graded grails, typo'd listings) — all of which work today.
    everything = (
        [*watchlist, cheapest, ending]
        if full
        else [
            *watchlist,
            *hidden_gem_targets(max_price=max_price),
            *sealed_sweep_targets(max_price=max_price),
            *graded_sweep_targets(max_price=max_price),
        ]
    )
    targets = {
        "watchlist": watchlist,
        "cheapest": [cheapest],
        "ending_soon": [ending],
        "hidden_gems": hidden_gem_targets(max_price=max_price),
        "graded": graded_sweep_targets(max_price=max_price),
        "sealed": sealed_sweep_targets(max_price=max_price),
        "everything": everything,
    }.get(body.mode, watchlist)

    return targets if full else [_basic_keyset_target(t) for t in targets]


@router.get("/watchlist")
def get_watchlist(request: Request) -> list[dict[str, Any]]:
    return [asdict(t) for t in request.app.state.watchlist]


@router.get("/quota")
def get_quota(request: Request) -> dict[str, Any]:
    q = request.app.state.quota
    return {"daily_budget": q.daily_budget, "used": q.used, "remaining": q.remaining}


def _execute_scan(
    request: Request,
    *,
    mode: str,
    targets: list[WatchTarget],
    cfg: PipelineConfig,
    max_valuations: int | None,
    against_card: Card | None = None,
) -> dict[str, Any]:
    """Run targets against eBay Browse, value + rank, and shape the JSON response.
    Shared by the watch-list scan and the single-card search. When ``against_card`` is
    set (card search) every listing is valued against that one card. eBay-fetch and
    sold-price failures are collected inside scan() (so partial results still come back),
    so this only hard-fails when eBay returned nothing at all."""
    source = build_browse_source(request.app.state.credentials, request.app.state.settings)
    if source is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Live eBay UK scanning isn't ready. Enable the 'eBay UK — Active listings' "
                "source and add your eBay API keys under Settings → Sources."
            ),
        )
    result = scan(
        targets,
        source,
        request.app.state.catalogue,
        request.app.state.sold_provider,
        quota=request.app.state.quota,
        cfg=cfg,
        max_valuations=(
            max_valuations
            if max_valuations is not None
            else request.app.state.settings.max_valuations_per_scan
        ),
        against_card=against_card,
    )

    # Nothing came back from eBay and every target errored — surface eBay's *real* error
    # (e.g. errorId 1100 "Insufficient permissions") instead of guessing at the cause.
    if result.listings_seen == 0 and result.errors:
        raise HTTPException(status_code=502, detail=_scan_error_detail(request, result.errors))

    # Momentum: compare to prior history, then record today's sample.
    attach_trends(request.app.state.session_maker, result.deals)
    record_snapshots(request.app.state.session_maker, result.deals)
    # Cache the freshly scanned deals so GET /deals reflects the live scan.
    request.app.state.deals = result.deals
    return {
        "mode": mode,
        "targets_scanned": result.targets_scanned,
        "calls_used": result.calls_used,
        "listings_seen": result.listings_seen,
        "new_listings": result.new_listings,
        "valued": result.valued,
        "unvalued": result.unvalued,
        "quota_exhausted": result.quota_exhausted,
        # Targets that failed (eBay 403, or valuation down) while the rest still returned.
        "errors": list(dict.fromkeys(result.errors)),
        "deals": [deal_to_dict(d) for d in result.deals],
    }


@router.post("/scan")
def run_scan(request: Request, body: ScanRequest | None = None) -> dict[str, Any]:
    body = body or ScanRequest()
    # Value a listing by its title even when it doesn't match the catalogue (flagged
    # UNVERIFIED), so a scan still finds deals before the full catalogue is imported.
    cfg = replace(request.app.state.pipeline_cfg, catalogue_free=True)
    if body.mode == "graded":
        cfg = replace(cfg, rules=RuleSet.for_holds())  # surface holds across all grades
    return _execute_scan(
        request,
        mode=body.mode,
        targets=_targets_for(request, body),
        cfg=cfg,
        max_valuations=body.max_valuations,
    )


class CardScanIn(BaseModel):
    query: str
    graded: bool = False
    include_misspellings: bool = False
    max_price: float | None = None
    max_valuations: int | None = None


def _misspelled_queries(query: str, limit: int = 4) -> list[str]:
    """Typo'd variants of the card *name* (numeric tokens dropped): sellers who mistype a
    title usually botch the name and omit the set number — the gem competitors miss."""
    name_tokens = [t for t in query.split() if not any(ch.isdigit() for ch in t)]
    if not name_tokens:
        return []
    head, *tail = name_tokens
    suffix = (" " + " ".join(tail)) if tail else ""
    return [f"{typo}{suffix}" for typo in misspellings(head, limit)]


def _card_targets(
    query: str, *, graded: bool, include_misspellings: bool, max_price: float | None
) -> list[WatchTarget]:
    queries = [query]
    if graded:
        queries += [f"{query} PSA", f"{query} CGC"]
    if include_misspellings:
        queries += _misspelled_queries(query)
    buying = ("FIXED_PRICE", "BEST_OFFER", "AUCTION")
    return [
        WatchTarget(
            query=q,
            buying_options=buying,
            sort="price",
            max_price=max_price,
            limit=100,
            priority=5 if q == query else 3,
        )
        for q in dict.fromkeys(q for q in queries if q.strip())  # de-dupe, keep order
    ]


@router.post("/scan/card")
def scan_card(request: Request, body: CardScanIn) -> dict[str, Any]:
    """Live-search eBay UK for one specific card — a keyword search, which works on a
    standard keyset (no category browsing) — then value the listings and rank them.
    Optional graded (PSA/CGC) and misspelt-listing variants."""
    query = body.query.strip()
    if len(query) < 3:
        raise HTTPException(status_code=400, detail="Type a card to search (3+ characters).")
    # An explicit card search is never "bulk" — drop the min-market-value floor.
    exact_rules = replace(request.app.state.pipeline_cfg.rules, min_market_value=Money.gbp(0))
    cfg = replace(request.app.state.pipeline_cfg, catalogue_free=True, rules=exact_rules)
    if body.graded:
        cfg = replace(cfg, rules=RuleSet.for_holds())
    targets = _card_targets(
        query,
        graded=body.graded,
        include_misspellings=body.include_misspellings,
        max_price=body.max_price,
    )
    # Value every listing against the one card the user searched for (clean identity →
    # the sold-price lookup actually returns comps), dropping wrong-number variants.
    card = resolve_searched_card(query, request.app.state.catalogue, cfg)
    return _execute_scan(
        request,
        mode=f"card:{query}",
        targets=targets,
        cfg=cfg,
        max_valuations=body.max_valuations,
        against_card=card,
    )


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
    # bundled catalogue. An explicit check is never "bulk" — drop the value floor too.
    exact_rules = replace(request.app.state.pipeline_cfg.rules, min_market_value=Money.gbp(0))
    cfg = replace(request.app.state.pipeline_cfg, catalogue_free=True, rules=exact_rules)
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
