"""Idempotent alert dispatch.

Sends the top passing deals via an :class:`AlertChannel`, recording each in the
``alerts`` table so the same listing never alerts twice on the same channel —
even across restarts. Dedup key = the listing's external id.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import sessionmaker

from ..core.models import Deal
from ..db.models import AlertRow
from ..providers.base import AlertChannel


def dispatch_alerts(
    deals: list[Deal],
    channel: AlertChannel,
    session_maker: sessionmaker,
    *,
    channel_name: str,
    limit: int = 10,
) -> int:
    """Send up to ``limit`` not-yet-alerted passing deals. Returns the count sent."""
    passing = [d for d in deals if d.passed_rules][:limit]
    sent = 0
    with session_maker() as session:
        for deal in passing:
            key = deal.listing.external_id
            already = session.scalar(
                select(AlertRow).where(
                    AlertRow.channel == channel_name, AlertRow.dedup_key == key
                )
            )
            if already is not None:
                continue
            channel.send(deal)  # may raise on network error -> retried next cycle
            card = deal.identification.card
            session.add(
                AlertRow(
                    channel=channel_name,
                    dedup_key=key,
                    deal_id=deal.id,
                    card=card.name if card else "",
                    profit=deal.economics.profit.as_float if deal.economics else 0.0,
                )
            )
            session.commit()
            sent += 1
    return sent
