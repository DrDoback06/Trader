"""eBay Sell (Inventory API) client — list a card you own.

Compliant by design: this lists the seller's OWN inventory on their OWN account
(user-OAuth token, `sell.inventory` scope), at their target price, with their own
photos. It is the sanctioned listing path — distinct from buying, which stays
manual. Flow: createOrReplaceInventoryItem -> createOffer -> publishOffer.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

import httpx

from ..services.relist import ListingDraft


@dataclass(frozen=True)
class SellConfig:
    marketplace_id: str = "EBAY_GB"
    fulfillment_policy_id: str = ""
    payment_policy_id: str = ""
    return_policy_id: str = ""
    merchant_location_key: str = ""

    @property
    def configured(self) -> bool:
        return all(
            (
                self.fulfillment_policy_id,
                self.payment_policy_id,
                self.return_policy_id,
                self.merchant_location_key,
            )
        )


@dataclass(frozen=True)
class RelistResult:
    sku: str
    offer_id: str
    listing_id: str | None
    url: str | None


def _to_float(value: Any) -> float | None:
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


class EbaySellClient:
    name = "ebay_sell"

    def __init__(
        self,
        user_token: str,
        sell_base: str,
        config: SellConfig,
        *,
        client: httpx.Client | None = None,
    ) -> None:
        self._token = user_token
        self._base = sell_base.rstrip("/")
        self._cfg = config
        self._client = client or httpx.Client(timeout=30.0)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Content-Language": "en-GB",
            "X-EBAY-C-MARKETPLACE-ID": self._cfg.marketplace_id,
        }

    def my_active_listings(self, *, limit: int = 200) -> list[dict[str, Any]]:
        """The seller's own inventory offers, as ``{title, item_id, url, price, sku}``.

        Honest limitation: the Sell *Inventory* API only returns offers created through
        the API (createOffer/publishOffer) — listings made in eBay's normal web UI won't
        appear here. The user can still add those as manual links. We page through
        ``/offer`` and keep the published ones.
        """
        out: list[dict[str, Any]] = []
        offset = 0
        page = min(100, limit)
        while len(out) < limit:
            resp = self._client.get(
                f"{self._base}/offer",
                headers=self._headers(),
                params={
                    "marketplace_id": self._cfg.marketplace_id,
                    "limit": page,
                    "offset": offset,
                },
            )
            resp.raise_for_status()
            body = resp.json()
            offers = body.get("offers") or []
            for offer in offers:
                listing_id = offer.get("listing", {}).get("listingId") or offer.get("listingId")
                price = (offer.get("pricingSummary") or {}).get("price") or {}
                title = (offer.get("listingDescription") or offer.get("sku") or "").strip()
                url = f"https://www.ebay.co.uk/itm/{listing_id}" if listing_id else None
                out.append(
                    {
                        "sku": offer.get("sku", ""),
                        "item_id": str(listing_id) if listing_id else None,
                        "title": title,
                        "url": url,
                        "price": _to_float(price.get("value")),
                    }
                )
            if len(offers) < page:
                break
            offset += page
        return out

    def relist(self, draft: ListingDraft, image_urls: Sequence[str]) -> RelistResult:
        # 1. Inventory item (the product + condition + quantity).
        inv = self._client.put(
            f"{self._base}/inventory_item/{draft.sku}",
            headers=self._headers(),
            json={
                "availability": {"shipToLocationAvailability": {"quantity": draft.quantity}},
                "condition": draft.condition,
                "product": {
                    "title": draft.title,
                    "description": draft.description,
                    "imageUrls": list(image_urls),
                },
            },
        )
        inv.raise_for_status()

        # 2. Offer (price + business policies + location).
        offer = self._client.post(
            f"{self._base}/offer",
            headers=self._headers(),
            json={
                "sku": draft.sku,
                "marketplaceId": self._cfg.marketplace_id,
                "format": "FIXED_PRICE",
                "availableQuantity": draft.quantity,
                "categoryId": draft.category_id,
                "listingDescription": draft.description,
                "pricingSummary": {
                    "price": {
                        "value": str(draft.price.amount),
                        "currency": draft.price.currency,
                    }
                },
                "listingPolicies": {
                    "fulfillmentPolicyId": self._cfg.fulfillment_policy_id,
                    "paymentPolicyId": self._cfg.payment_policy_id,
                    "returnPolicyId": self._cfg.return_policy_id,
                },
                "merchantLocationKey": self._cfg.merchant_location_key,
            },
        )
        offer.raise_for_status()
        offer_id: Any = offer.json().get("offerId", "")

        # 3. Publish -> active listing.
        published = self._client.post(
            f"{self._base}/offer/{offer_id}/publish", headers=self._headers()
        )
        published.raise_for_status()
        listing_id: Any = published.json().get("listingId")
        url = f"https://www.ebay.co.uk/itm/{listing_id}" if listing_id else None
        return RelistResult(sku=draft.sku, offer_id=str(offer_id), listing_id=listing_id, url=url)
