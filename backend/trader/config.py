"""Application settings (env-driven). The pure core does not import this."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "dev"
    log_level: str = "INFO"

    # Phase 1
    total_budget_gbp: float = 300.0
    soldprice_provider: str = "fixture"
    alert_channel: str = "console"


@lru_cache
def get_settings() -> Settings:
    return Settings()
