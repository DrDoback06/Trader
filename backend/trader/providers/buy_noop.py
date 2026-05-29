"""No-op buy executor — automated buying is intentionally disabled.

eBay does not grant automated-purchase API access to small operators, and
bot-buying breaches eBay's User Agreement. The only buy path is a human clicking
the listing URL. This seam exists purely so a compliant executor *could* be added
later if official access is ever obtained.
"""

from __future__ import annotations

from ..core.models import ListingFacts


class NoOpBuyExecutor:
    def buy(self, listing: ListingFacts) -> None:
        raise NotImplementedError(
            "Automated buying is disabled by design (human-in-the-loop). "
            f"Open the listing and buy manually: {listing.url or listing.external_id}"
        )
