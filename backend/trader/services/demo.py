"""Build a ranked set of demo deals from the bundled sample data (no keys)."""

from __future__ import annotations

from pathlib import Path

from ..core.models import Deal
from ..identify.catalogue import Catalogue
from ..providers.soldprice_fixture import FixtureSoldPriceProvider
from .loaders import load_listings
from .pipeline import PipelineConfig, run_pipeline

_PKG_ROOT = Path(__file__).resolve().parent.parent  # .../trader


def load_catalogue() -> Catalogue:
    """Use the locally imported full catalogue if present, else the seed sets.

    Ignore importer checkpoint files (``_import_state.json``): a half-finished or
    aborted ``--catalogue`` import can leave only that file behind, which must NOT
    count as "imported" — otherwise the catalogue loads empty and Browse shows
    nothing. Fall back to the bundled seed sets whenever no real cards load."""
    imported = _PKG_ROOT / "catalogue_data" / "imported"
    has_real_sets = imported.is_dir() and any(
        not p.name.startswith("_") for p in imported.glob("*.json")
    )
    if has_real_sets:
        cat = Catalogue.from_dir(imported)
        if len(cat) > 0:
            return cat
    return Catalogue.from_dir(_PKG_ROOT / "catalogue_data" / "pokemon")


def load_sold_provider() -> FixtureSoldPriceProvider:
    return FixtureSoldPriceProvider.from_file(_PKG_ROOT / "sample_data" / "sold_prices.json")


def build_demo_deals(cfg: PipelineConfig | None = None) -> list[Deal]:
    listings = load_listings(_PKG_ROOT / "sample_data" / "demo_listings.json")
    return run_pipeline(listings, load_catalogue(), load_sold_provider(), cfg)
