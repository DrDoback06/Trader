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
from .alert_console import ConsoleAlertChannel
from .alert_telegram import TelegramAlertChannel
from .base import AlertChannel, SoldPriceProvider, VisionIdentifier
from .ebay_browse import EbayBrowseSource
from .ebay_oauth import EbayOAuth
from .ebay_sell import EbaySellClient, SellConfig
from .soldprice_rapidapi import RapidApiSoldPriceProvider
from .vision_claude import ClaudeVisionIdentifier

_SANDBOX_OAUTH = "https://api.sandbox.ebay.com/identity/v1/oauth2/token"
_SANDBOX_BROWSE = "https://api.sandbox.ebay.com/buy/browse/v1"
_SANDBOX_SELL = "https://api.sandbox.ebay.com/sell/inventory/v1"


def build_sell_client(
    credentials: CredentialStore, settings: Settings
) -> EbaySellClient | None:
    """eBay Sell client for relisting, or None if not enabled/keyed."""
    if not (credentials.is_enabled("relist") and credentials.is_configured("ebay_user_token")):
        return None
    base = _SANDBOX_SELL if settings.ebay_env == "sandbox" else settings.ebay_sell_base
    config = SellConfig(
        marketplace_id=settings.ebay_marketplace_id,
        fulfillment_policy_id=settings.ebay_fulfillment_policy_id,
        payment_policy_id=settings.ebay_payment_policy_id,
        return_policy_id=settings.ebay_return_policy_id,
        merchant_location_key=settings.ebay_merchant_location_key,
    )
    return EbaySellClient(credentials.get("ebay_user_token"), base, config)


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


def build_alert_channel(settings: Settings) -> AlertChannel:
    """Telegram when configured, else the console channel."""
    if (
        settings.alert_channel == "telegram"
        and settings.telegram_bot_token
        and settings.telegram_chat_id
    ):
        return TelegramAlertChannel(settings.telegram_bot_token, settings.telegram_chat_id)
    return ConsoleAlertChannel()


def build_vision_provider(
    credentials: CredentialStore, settings: Settings
) -> VisionIdentifier | None:
    """Claude vision identifier when enabled + keyed + the SDK is installed."""
    if not (credentials.is_enabled("vision") and credentials.is_configured("anthropic_api_key")):
        return None
    try:
        import anthropic  # noqa: F401 -- presence check for the optional [vision] extra
    except ImportError:
        return None
    return ClaudeVisionIdentifier(
        credentials.get("anthropic_api_key"), model=settings.anthropic_vision_model
    )


def configure_app_providers(app: Any) -> None:
    """(Re)build providers held in app.state after any credential/source change."""
    app.state.sold_provider = build_sold_provider(app.state.credentials, app.state.settings)
    app.state.pipeline_cfg.vision = build_vision_provider(app.state.credentials, app.state.settings)
