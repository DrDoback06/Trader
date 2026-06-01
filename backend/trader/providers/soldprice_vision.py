"""Claude-AI rough-estimate sold-price provider.

Last-resort valuation rung. When eBay-UK sold prices (RapidAPI) and the free
pokemontcg.io market reference both miss — typically for **graded slabs**, which
pokemontcg.io can't price, or for niche promos — this asks Claude for a single
GBP estimate based on its general knowledge of UK TCG pricing.

Honest limits:
* Not real comps. Confidence is heavily capped (small effective sample size +
  wide baseline spread), and the verdict is flagged ``provider="claude_estimate"``
  so the UI can label it ``est. (rough)`` and never confuse it with real
  sold-price data.
* Each call uses the Claude API, so it's gated by a per-condition cache (the
  wrapping :class:`CachingSoldPriceProvider`) — fires at most once per
  (card, condition) per TTL.
* If the SDK is missing or the call fails for any reason we return ``None`` so the
  caller can show "valuation unavailable" instead of crashing the pipeline.
"""

from __future__ import annotations

import json
import re

from ..core.models import Card, Valuation
from ..core.money import Money

_ROUGH_SAMPLE_SIZE = 3
_ROUGH_SPREAD = 0.45

_PROMPT_TEMPLATE = (
    "You are pricing a single trading card for resale on eBay UK in GBP.\n"
    "Card name: {name}\n"
    "Set: {set_name} ({set_code})\n"
    "Number: {number}\n"
    "Rarity: {rarity}\n"
    "Condition bucket: {condition}\n"
    "{grading_note}"
    "Reply with ONLY a JSON object on a single line:\n"
    '{{"median_gbp": <number>, "low_gbp": <number>, "high_gbp": <number>, '
    '"confidence": "low|medium|high"}}\n'
    "Use median_gbp = your best single GBP estimate of the recent eBay UK sold price for "
    "this card in this exact condition. Low/high should bracket plausible variation. If you "
    'genuinely do not know, reply with {{"median_gbp": 0}}.'
)


def _grading_note(condition_key: str) -> str:
    if not condition_key.startswith("GRADED_"):
        return ""
    parts = condition_key.split("_")
    if len(parts) >= 3:
        company, grade = parts[1], parts[2]
        return f"This is a {company} {grade} graded slab — value the slab, not a raw card.\n"
    return "This is a graded slab — value the slab, not a raw card.\n"


def _parse_response(text: str) -> tuple[float, float | None, float | None] | None:
    """Extract (median, low, high) from Claude's reply, tolerating extra prose."""
    match = re.search(r"\{[^{}]*\}", text)
    if not match:
        return None
    try:
        payload = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    median = payload.get("median_gbp")
    if not isinstance(median, (int, float)) or median <= 0:
        return None
    low = payload.get("low_gbp")
    high = payload.get("high_gbp")
    low_f = float(low) if isinstance(low, (int, float)) and low > 0 else None
    high_f = float(high) if isinstance(high, (int, float)) and high > 0 else None
    return float(median), low_f, high_f


class ClaudeEstimateProvider:
    """Rough-estimate sold-price provider backed by the Claude API."""

    name = "claude_estimate"

    def __init__(self, api_key: str, *, model: str = "claude-opus-4-7") -> None:
        self._api_key = api_key
        self._model = model

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        try:
            import anthropic
        except ImportError:
            return None

        prompt = _PROMPT_TEMPLATE.format(
            name=card.name,
            set_name=card.set_name or "(unknown)",
            set_code=card.set_code or "?",
            number=card.number or "?",
            rarity=card.rarity or "(unknown)",
            condition=condition_key,
            grading_note=_grading_note(condition_key),
        )
        try:
            client = anthropic.Anthropic(api_key=self._api_key)
            resp = client.messages.create(
                model=self._model,
                max_tokens=200,
                messages=[{"role": "user", "content": prompt}],
            )
        except Exception:
            return None

        text = ""
        for block in getattr(resp, "content", []) or []:
            if getattr(block, "type", "") == "text":
                text += getattr(block, "text", "")
        parsed = _parse_response(text)
        if parsed is None:
            return None
        median, low, high = parsed

        median_m = Money.of(f"{median:.2f}", "GBP")
        low_m = Money.of(f"{low:.2f}", "GBP") if low is not None else None
        high_m = Money.of(f"{high:.2f}", "GBP") if high is not None else None
        spread = _ROUGH_SPREAD
        if low_m is not None and high_m is not None and median_m.amount > 0:
            spread = max(
                _ROUGH_SPREAD,
                float((high_m.amount - low_m.amount) / median_m.amount),
            )

        return Valuation(
            card_id=card.id,
            condition_key=condition_key,
            provider=self.name,
            median=median_m,
            average=median_m,
            low=low_m,
            high=high_m,
            sample_size=_ROUGH_SAMPLE_SIZE,
            spread=round(spread, 3),
            currency="GBP",
        )
