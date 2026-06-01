"""Registry of UK TCG price / insight sources shown in the UI.

Only sources we're confident are accurate for the UK are ``available`` (wired and
usable). Others are listed for transparency but cannot be enabled, with the reason
why — so the UI can show every option without ever using a misleading one.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SourceInfo:
    id: str
    name: str
    role: str  # "Market value" | "Deal discovery" | "Cross-check"
    region: str
    currency: str
    requires: tuple[str, ...]  # credential keys needed to use it
    signup_url: str
    accuracy: str
    available: bool  # wired and trustworthy for the UK
    default_enabled: bool


SOURCES: list[SourceInfo] = [
    SourceInfo(
        id="pokemontcg_market",
        name="Free market price (pokemontcg.io)",
        role="Market value",
        region="EU/US",
        currency="GBP",
        requires=(),
        signup_url="https://pokemontcg.io/",
        accuracy="Free, no key — Cardmarket/TCGplayer reference price in GBP. A quick "
        "is-this-underpriced gauge, not real eBay-UK sold prices.",
        available=True,
        default_enabled=True,
    ),
    SourceInfo(
        id="ebay_uk_sold",
        name="eBay UK — Sold prices",
        role="Market value",
        region="UK",
        currency="GBP",
        requires=("rapidapi_key",),
        signup_url="https://rapidapi.com/ecommet/api/ebay-average-selling-price",
        accuracy="Most accurate UK value — real eBay.co.uk sold prices (avg/median). "
        "Used first when keyed, with the free source as automatic fallback.",
        available=True,
        default_enabled=True,
    ),
    SourceInfo(
        id="ebay_uk_active",
        name="eBay UK — Active listings",
        role="Deal discovery",
        region="UK",
        currency="GBP",
        requires=("ebay_client_id", "ebay_client_secret"),
        signup_url="https://developer.ebay.com/join/",
        accuracy="Live UK asking prices — finds underpriced listings, not a standalone value.",
        available=True,
        default_enabled=True,
    ),
    SourceInfo(
        id="vision",
        name="Photo ID (Claude AI)",
        role="Identification",
        region="AI",
        currency="—",
        requires=("anthropic_api_key",),
        signup_url="https://console.anthropic.com/",
        accuracy="Reads the card from the listing photo when the title is too vague to match.",
        available=True,
        default_enabled=False,
    ),
    SourceInfo(
        id="relist",
        name="eBay relist (Sell API)",
        role="Sell",
        region="UK",
        currency="GBP",
        requires=("ebay_user_token",),
        signup_url="https://developer.ebay.com/api-docs/sell/static/inventory/inventory-item-to-offer.html",
        accuracy="Lists cards you own via eBay's Sell API — your account, your photos.",
        available=True,
        default_enabled=False,
    ),
    SourceInfo(
        id="cardmarket",
        name="Cardmarket (Europe)",
        role="Market value",
        region="EU",
        currency="EUR",
        requires=(),
        signup_url="https://help.cardmarket.com/en/cardmarket-api",
        accuracy="Largest EU marketplace, but its API is closed to new devs; prices are EUR.",
        available=False,
        default_enabled=False,
    ),
    SourceInfo(
        id="pricecharting",
        name="PriceCharting (US)",
        role="Cross-check",
        region="US",
        currency="USD",
        requires=("pricecharting_api_key",),
        signup_url="https://www.pricecharting.com/api-documentation",
        accuracy="US-centric USD prices — not representative of the UK market.",
        available=False,
        default_enabled=False,
    ),
]

SOURCES_BY_ID: dict[str, SourceInfo] = {s.id: s for s in SOURCES}
DEFAULT_ENABLED: set[str] = {s.id for s in SOURCES if s.default_enabled}
