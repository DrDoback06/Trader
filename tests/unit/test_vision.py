from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from trader.core.models import Card, ListingFacts, Valuation, VisionCard
from trader.core.money import Money
from trader.identify.catalogue import Catalogue
from trader.providers.vision_claude import ClaudeVisionIdentifier
from trader.services.pipeline import PipelineConfig, evaluate_listing


class _FakeMessages:
    def parse(self, **kwargs: Any) -> Any:
        return SimpleNamespace(
            parsed_output=SimpleNamespace(
                name="Charizard ex",
                number="199/165",
                set_name="151",
                condition="Near Mint",
                confidence=0.92,
            )
        )


class _FakeAnthropic:
    messages = _FakeMessages()


def test_vision_identifier_maps_structured_output() -> None:
    vision = ClaudeVisionIdentifier("KEY", client=_FakeAnthropic())
    out = vision.identify("https://img/x.jpg", "blurry title")
    assert out is not None
    assert out.name == "Charizard ex"
    assert out.number == "199/165"
    assert out.confidence > 0.9


class _FakeVision:
    name = "vision"

    def identify(self, image_url: str, title: str = "") -> VisionCard | None:
        return VisionCard(name="Charizard ex", number="199/165", set_name="151", confidence=0.9)


class _FixtureProvider:
    name = "fixture"

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        return Valuation(
            card_id=card.id, condition_key=condition_key, provider="fixture",
            median=Money.gbp(80), sample_size=12,
        )


def test_pipeline_uses_vision_for_vague_title(catalogue: Catalogue) -> None:
    listing = ListingFacts(
        external_id="v1",
        title="rare pokemon card l@@k rare",  # no number -> won't match by title
        price=Money.gbp(40),
        condition_raw="Near Mint",
        image_url="https://img/x.jpg",
    )
    cfg = PipelineConfig(vision=_FakeVision())
    deal = evaluate_listing(listing, catalogue, _FixtureProvider(), cfg)

    assert deal.identification.card is not None
    assert deal.identification.card.number == "199/165"
    assert "VISION" in deal.identification.parsed.flags


def test_pipeline_skips_vision_without_image(catalogue: Catalogue) -> None:
    listing = ListingFacts(external_id="v2", title="rare pokemon l@@k", price=Money.gbp(40))
    cfg = PipelineConfig(vision=_FakeVision())
    deal = evaluate_listing(listing, catalogue, _FixtureProvider(), cfg)
    assert deal.identification.card is None  # no image -> vision not attempted
