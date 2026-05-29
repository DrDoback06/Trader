"""Build providers from runtime credentials + settings, and wire them into app state.

UI-entered keys (held in the CredentialStore) take precedence and take effect
immediately — no restart needed.
"""

from __future__ import annotations

from typing import Any

from ..config import Settings
from ..services.credentials import CredentialStore
from ..services.demo import load_sold_provider
from ..services.valuation import CachingSoldPriceProvider
from .base import SoldPriceProvider
from .ebay_browse import EbayBrowseSource
from .ebay_oauth import EbayOAuth
from .soldprice_rapidapi import RapidApiSoldPriceProvider

_SANDBOX_OAUTH = "https://api.sandbox.ebay.com/identity/v1/oauth2/token"
_SANDBOX_BROWSE = "https://api.sandbox.ebay.com/buy/browse/v1"


def _bases(settings: Settings) -> tuple[str, str]:
    if settings.ebay_env == "sandbox":
        return _SANDBOX_OAUTH, _SANDBOX_BROWSE
    return settings.ebay_oauth_base, settings.ebay_browse_base


def build_browse_source(
    credentials: CredentialStore, settings: Settings
) -> EbayBrowseSource | None:
    """The eBay Browse source, or None if the active-listings source isn't ready."""
    if not credentials.is_enabled("ebay_uk_active"):
        return None
    if not credentials.is_configured("ebay_client_id", "ebay_client_secret"):
        return None
    oauth_url, browse_url = _bases(settings)
    oauth = EbayOAuth(
        credentials.get("ebay_client_id"), credentials.get("ebay_client_secret"), oauth_url
    )
    return EbayBrowseSource(oauth, browse_url, marketplace_id=settings.ebay_marketplace_id)


def build_sold_provider(
    credentials: CredentialStore, settings: Settings
) -> SoldPriceProvider:
    """Live eBay-UK sold prices when configured + enabled, else the offline fixture."""
    if credentials.is_enabled("ebay_uk_sold") and credentials.is_configured("rapidapi_key"):
        inner = RapidApiSoldPriceProvider(
            credentials.get("rapidapi_key"),
            host=settings.rapidapi_soldprice_host,
            site_id=settings.soldprice_site_id,
        )
        return CachingSoldPriceProvider(inner, ttl_hours=settings.valuation_ttl_hours)
    return load_sold_provider()


def configure_app_providers(app: Any) -> None:
    """(Re)build providers held in app.state after any credential/source change."""
    app.state.sold_provider = build_sold_provider(app.state.credentials, app.state.settings)
