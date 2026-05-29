"""FastAPI application factory.

Phase 1 serves ranked *demo* deals from bundled sample data (no API keys).
Phase 2 adds `POST /scan` for live eBay UK scanning. Phase 3 adds live eBay-UK
sold-price valuation. Keys are entered via the UI (`/sources`) and applied at
runtime; the catalogue and selected providers are shared across paths.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import deals as deals_api
from .api import health as health_api
from .api import scan as scan_api
from .api import settings as settings_api
from .api import sources as sources_api
from .config import get_settings
from .providers.factory import configure_app_providers
from .services.credentials import CredentialStore
from .services.demo import build_demo_deals, load_catalogue
from .services.pipeline import PipelineConfig
from .services.quota import DailyQuota
from .services.sources import DEFAULT_ENABLED
from .services.watchlist import default_watchlist


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
    app.state.quota = DailyQuota(settings.ebay_daily_call_budget)
    app.state.credentials = CredentialStore.create(
        settings, DEFAULT_ENABLED, path=Path(settings.credentials_path)
    )
    # Selects live eBay-UK sold prices when configured, else the offline fixture.
    configure_app_providers(app)
    # Start with demo deals so the dashboard has content before the first live scan.
    app.state.deals = build_demo_deals(app.state.pipeline_cfg)

    app.include_router(health_api.router)
    app.include_router(deals_api.router)
    app.include_router(settings_api.router)
    app.include_router(scan_api.router)
    app.include_router(sources_api.router)
    return app


app = create_app()
