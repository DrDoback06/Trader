"""Telegram alert channel — pushes a deal to a chat via the Bot API."""

from __future__ import annotations

import httpx

from ..core.models import Deal


class TelegramAlertChannel:
    name = "telegram"

    def __init__(self, bot_token: str, chat_id: str, client: httpx.Client | None = None) -> None:
        self._token = bot_token
        self._chat_id = chat_id
        self._client = client or httpx.Client(timeout=15.0)

    def _format(self, deal: Deal) -> str:
        card = deal.identification.card
        name = card.name if card else "(card)"
        est = deal.valuation.median if deal.valuation else "?"
        econ = deal.economics
        profit = econ.profit if econ else "?"
        roi = f"{econ.roi:.0%}" if econ else "?"
        bid = f" · max bid {deal.max_bid}" if deal.max_bid else ""
        return (
            f"🟢 {name} — ask {deal.listing.price} → est {est}\n"
            f"Profit {profit} ({roi} ROI){bid}\n"
            f"{deal.listing.url or ''}"
        )

    def send(self, deal: Deal) -> None:
        resp = self._client.post(
            f"https://api.telegram.org/bot{self._token}/sendMessage",
            json={"chat_id": self._chat_id, "text": self._format(deal)},
        )
        resp.raise_for_status()
