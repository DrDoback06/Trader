"""Vision-assisted card identification via the Claude API.

When a listing's title is too vague to match but it has a photo, ask Claude to
read the card from the image. Called only on otherwise-unmatched listings, so the
per-call cost is bounded. Uses structured output (messages.parse) and caches the
(stable) system prompt.

`anthropic` is an optional dependency — install with the `[vision]` extra. The SDK
is imported lazily so the rest of the app runs without it.
"""

from __future__ import annotations

from typing import Any

from ..core.models import VisionCard

_SYSTEM = (
    "You identify Pokémon trading cards from a marketplace photo. Return the card "
    "name, its collector number in NN/NN form if visible (e.g. 199/165), the set "
    "name if recognisable, the raw condition (Near Mint / Lightly Played / "
    "Moderately Played / Heavily Played / Damaged) or the grade if slabbed, and a "
    "confidence in [0,1]. Be conservative: if you cannot read the card clearly, "
    "return a low confidence. Do not guess a number you cannot see."
)


class ClaudeVisionIdentifier:
    name = "vision"

    def __init__(self, api_key: str, *, model: str = "claude-opus-4-8", client: Any = None) -> None:
        self._api_key = api_key
        self._model = model
        self._client = client

    def _ensure_client(self) -> Any:
        if self._client is None:
            import anthropic  # lazy: optional dependency

            self._client = anthropic.Anthropic(api_key=self._api_key)
        return self._client

    def identify(self, image_url: str, title: str = "") -> VisionCard | None:
        from pydantic import BaseModel

        class _Out(BaseModel):
            name: str
            number: str | None = None
            set_name: str | None = None
            condition: str | None = None
            confidence: float

        try:
            response = self._ensure_client().messages.parse(
                model=self._model,
                max_tokens=512,
                system=[
                    {"type": "text", "text": _SYSTEM, "cache_control": {"type": "ephemeral"}}
                ],
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "image", "source": {"type": "url", "url": image_url}},
                            {"type": "text", "text": f"Listing title: {title}\nIdentify the card."},
                        ],
                    }
                ],
                output_format=_Out,
            )
        except Exception:  # best-effort enrichment — never break a scan
            return None

        out = getattr(response, "parsed_output", None)
        if out is None or not out.name:
            return None
        return VisionCard(
            name=out.name,
            number=out.number,
            set_name=out.set_name,
            condition=out.condition,
            confidence=float(out.confidence),
        )
