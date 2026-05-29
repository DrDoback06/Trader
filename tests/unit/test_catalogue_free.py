from __future__ import annotations

from trader.core.models import Card, ListingFacts, Valuation
from trader.core.money import Money
from trader.identify.catalogue import Catalogue
from trader.services.pipeline import PipelineConfig, evaluate_listing


class _FreeProvider:
    name = "free"

    def get_valuation(self, card: Card, condition_key: str) -> Valuation | None:
        return Valuation(
            card_id=card.id, condition_key=condition_key, provider="free",
            median=Money.gbp(120), sample_size=12,
        )


_SEALED = ListingFacts(
    external_id="s1",
    title="Pokemon 151 Booster Box Sealed",
    price=Money.gbp(60),
    condition_raw="New",
)


def test_unmatched_is_rejected_without_catalogue_free(catalogue: Catalogue) -> None:
    deal = evaluate_listing(_SEALED, catalogue, _FreeProvider(), PipelineConfig())
    assert deal.valuation is None
    assert "identification" in "; ".join(deal.rule_reasons)


def test_catalogue_free_values_sealed_by_title(catalogue: Catalogue) -> None:
    deal = evaluate_listing(
        _SEALED, catalogue, _FreeProvider(), PipelineConfig(catalogue_free=True)
    )
    assert deal.valuation is not None
    assert deal.economics is not None
    assert "UNVERIFIED" in deal.identification.parsed.flags
