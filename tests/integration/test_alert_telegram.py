from __future__ import annotations

import json
from collections.abc import Callable

import httpx
import respx

from trader.core.models import Deal
from trader.providers.alert_telegram import TelegramAlertChannel


@respx.mock
def test_telegram_send_posts_message(make_deal: Callable[..., Deal]) -> None:
    route = respx.post("https://api.telegram.org/botTOKEN/sendMessage").mock(
        return_value=httpx.Response(200, json={"ok": True})
    )
    channel = TelegramAlertChannel("TOKEN", "CHAT")
    deal = make_deal(profit=10, roi=0.5, margin=0.3, confidence=0.8)

    channel.send(deal)

    assert route.called
    body = json.loads(route.calls.last.request.content)
    assert body["chat_id"] == "CHAT"
    assert "Charizard ex" in body["text"]  # the make_deal card name
