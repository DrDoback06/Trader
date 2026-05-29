"""Build an ``EbayBrowseSource`` from settings, or ``None`` if not configured."""

from __future__ import annotations

from ..config import Settings
from .ebay_browse import EbayBrowseSource
from .ebay_oauth import EbayOAuth

_SANDBOX_OAUTH = "https://api.sandbox.ebay.com/identity/v1/oauth2/token"
_SANDBOX_BROWSE = "https://api.sandbox.ebay.com/buy/browse/v1"


def _bases(settings: Settings) -> tuple[str, str]:
    if settings.ebay_env == "sandbox":
        return _SANDBOX_OAUTH, _SANDBOX_BROWSE
    return settings.ebay_oauth_base, settings.ebay_browse_base


def build_browse_source(settings: Settings) -> EbayBrowseSource | None:
    if not settings.ebay_configured:
        return None
    oauth_url, browse_url = _bases(settings)
    oauth = EbayOAuth(settings.ebay_client_id, settings.ebay_client_secret, oauth_url)
    return EbayBrowseSource(oauth, browse_url, marketplace_id=settings.ebay_marketplace_id)
