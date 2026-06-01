"""FastAPI application factory.

Phase 1 serves ranked *demo* deals from bundled sample data (no API keys).
Phase 2 adds `POST /scan` for live eBay UK scanning. Phase 3 adds live eBay-UK
sold-price valuation. Keys are entered via the UI (`/sources`) and applied at
runtime; the catalogue and selected providers are shared across paths.
"""

from __future__ import annotations

import base64
import binascii
import hmac
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .api import alerts as alerts_api
from .api import catalogue as catalogue_api
from .api import collection as collection_api
from .api import deals as deals_api
from .api import health as health_api
from .api import portfolio as portfolio_api
from .api import scan as scan_api
from .api import settings as settings_api
from .api import sources as sources_api
from .config import get_settings
from .db.base import init_db, make_engine, session_factory
from .providers.factory import build_browse_source, configure_app_providers
from .services.cardlist import CardList
from .services.collection import Collection
from .services.credentials import CredentialStore
from .services.demo import build_demo_deals, load_catalogue
from .services.pipeline import PipelineConfig
from .services.quota import DailyQuota
from .services.scheduler import start_scheduler
from .services.sources import DEFAULT_ENABLED
from .services.watchlist import default_card_queries, default_watchlist


def _basic_auth_ok(header: str | None, password: str) -> bool:
    """True if the Authorization header carries the right Basic password."""
    if not header or not header.startswith("Basic "):
        return False
    try:
        decoded = base64.b64decode(header[6:]).decode()
    except (binascii.Error, ValueError):
        return False
    _, _, supplied = decoded.partition(":")  # any username; password must match
    return hmac.compare_digest(supplied, password)


def create_app() -> FastAPI:
    app = FastAPI(
        title="Trader API",
        version="0.3.0",
        description="UK TCG arbitrage decision-support — ranked underpriced card deals.",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # dev only; tighten for deployment
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    settings = get_settings()
    app.state.settings = settings
    app.state.pipeline_cfg = PipelineConfig()
    app.state.catalogue = load_catalogue()
    app.state.watchlist = default_watchlist()
    app.state.cardlist = CardList.create(
        Path(settings.cardlist_path), seed=default_card_queries()
    )
    app.state.collection = Collection.create(Path(settings.collection_path))
    app.state.quota = DailyQuota(settings.ebay_daily_call_budget)
    app.state.credentials = CredentialStore.create(
        settings, DEFAULT_ENABLED, path=Path(settings.credentials_path)
    )
    engine = make_engine(settings.database_url)
    init_db(engine)
    app.state.session_maker = session_factory(engine)
    # Selects live eBay-UK sold prices when configured, else the offline fixture.
    configure_app_providers(app)
    # Production-clean: only seed demo deals when there's no live listing source yet,
    # so first-time users see a populated UI but a configured account starts empty.
    live_listings = build_browse_source(app.state.credentials, app.state.settings) is not None
    app.state.deals = [] if live_listings else build_demo_deals(app.state.pipeline_cfg)
    # Recent "Check a card" evaluations, so those can be added to the portfolio too.
    app.state.recent_evals = {}

    @app.middleware("http")
    async def require_password(request: Request, call_next):
        password = request.app.state.settings.access_password
        is_open = request.method == "OPTIONS" or request.url.path == "/health"
        if password and not is_open and not _basic_auth_ok(
            request.headers.get("Authorization"), password
        ):
            return Response(
                status_code=401, headers={"WWW-Authenticate": 'Basic realm="Trader"'}
            )
        return await call_next(request)

    app.include_router(health_api.router)
    app.include_router(deals_api.router)
    app.include_router(settings_api.router)
    app.include_router(scan_api.router)
    app.include_router(sources_api.router)
    app.include_router(alerts_api.router)
    app.include_router(portfolio_api.router)
    app.include_router(catalogue_api.router)
    app.include_router(collection_api.router)

    # Periodically scour + alert when SCAN_INTERVAL_MIN > 0 and eBay is configured.
    app.state.scheduler = start_scheduler(app)

    # Serve the built dashboard from the same process, if it's been built.
    dist = Path(__file__).resolve().parents[2] / "frontend" / "dist"
    if (dist / "index.html").exists():
        app.mount("/", StaticFiles(directory=dist, html=True), name="frontend")

    return app


app = create_app()
