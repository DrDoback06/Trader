"""FastAPI application factory.

Phase 1 serves ranked *demo* deals computed from bundled sample data (no API keys
required), so the dashboard and the whole decision pipeline can be demonstrated
end-to-end offline. Phases 2-3 swap the demo builder for live scanning + valuation.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import deals as deals_api
from .api import health as health_api
from .api import settings as settings_api
from .services.demo import build_demo_deals
from .services.pipeline import PipelineConfig


def create_app() -> FastAPI:
    app = FastAPI(
        title="Trader API",
        version="0.1.0",
        description="UK TCG arbitrage decision-support — ranked underpriced card deals.",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # dev only; tighten for deployment
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.state.pipeline_cfg = PipelineConfig()
    app.state.deals = build_demo_deals(app.state.pipeline_cfg)

    app.include_router(health_api.router)
    app.include_router(deals_api.router)
    app.include_router(settings_api.router)
    return app


app = create_app()
