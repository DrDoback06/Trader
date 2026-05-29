"""Dev alert channel that prints deals to stdout."""

from __future__ import annotations

from ..core.models import Deal


class ConsoleAlertChannel:
    name = "console"

    def send(self, deal: Deal) -> None:
        card = deal.identification.card
        name = card.name if card else "(unidentified)"
        est = deal.valuation.median if deal.valuation else "?"
        profit = deal.economics.profit if deal.economics else "?"
        print(
            f"[DEAL] {name} — ask {deal.listing.price} -> est {est} | "
            f"profit {profit} | conf {deal.confidence:.2f} | {deal.listing.url}"
        )
