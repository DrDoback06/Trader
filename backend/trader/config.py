"""Application settings (env-driven). The pure core does not import this."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "dev"
    log_level: str = "INFO"
    # When set, the whole app (dashboard + API) is gated behind HTTP Basic auth.
    # Leave empty for open access (local dev / demo). `/health` is always open.
    access_password: str = ""

    # Phase 1
    total_budget_gbp: float = 300.0
    soldprice_provider: str = "fixture"
    alert_channel: str = "console"

    # Phase 2 — eBay Browse (live UK listing scanning)
    ebay_client_id: str = ""
    ebay_client_secret: str = ""
    ebay_env: str = "sandbox"  # sandbox | production
    ebay_marketplace_id: str = "EBAY_GB"
    ebay_oauth_base: str = "https://api.ebay.com/identity/v1/oauth2/token"
    ebay_browse_base: str = "https://api.ebay.com/buy/browse/v1"
    ebay_daily_call_budget: int = 4500

    # Phase 3 — sold-price valuation (eBay UK sold)
    rapidapi_key: str = ""
    rapidapi_soldprice_host: str = "ebay-average-selling-price.p.rapidapi.com"
    soldprice_site_id: str = "3"  # 3 = eBay UK (GBP)
    valuation_ttl_hours: int = 72
    pricecharting_api_key: str = ""

    # Where UI-entered keys are persisted (local, gitignored, plaintext).
    credentials_path: str = ".trader/credentials.json"

    @property
    def ebay_configured(self) -> bool:
        return bool(self.ebay_client_id and self.ebay_client_secret)


@lru_cache
def get_settings() -> Settings:
    return Settings()
