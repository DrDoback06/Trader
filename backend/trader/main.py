"""FastAPI application factory.

Phase 1 serves ranked *demo* deals from bundled sample data (no API keys).
Phase 2 adds `POST /scan` for live eBay UK scanning once credentials are set;
the catalogue and (for now, fixture) valuation are shared between both paths.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import deals as deals_api
from .api import health as health_api
from .api import scan as scan_api
from .api import settings as settings_api
from .config import get_settings
from .services.demo import build_demo_deals, load_catalogue, load_sold_provider
from .services.pipeline import PipelineConfig
from .services.quota import DailyQuota
from .services.watchlist import default_watchlist


def create_app() -> FastAPI:
    app = FastAPI(
        title="Trader API",
        version="0.2.0",
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
    app.state.sold_provider = load_sold_provider()  # Phase 3 swaps in live UK sold prices
    app.state.watchlist = default_watchlist()
    app.state.quota = DailyQuota(settings.ebay_daily_call_budget)
    # Start with demo deals so the dashboard has content before the first live scan.
    app.state.deals = build_demo_deals(app.state.pipeline_cfg)

    app.include_router(health_api.router)
    app.include_router(deals_api.router)
    app.include_router(settings_api.router)
    app.include_router(scan_api.router)
    return app


app = create_app()
