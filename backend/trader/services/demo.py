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
    """Use the locally imported full catalogue if present, else the seed sets."""
    imported = _PKG_ROOT / "catalogue_data" / "imported"
    if imported.is_dir() and any(imported.glob("*.json")):
        return Catalogue.from_dir(imported)
    return Catalogue.from_dir(_PKG_ROOT / "catalogue_data" / "pokemon")


def load_sold_provider() -> FixtureSoldPriceProvider:
    return FixtureSoldPriceProvider.from_file(_PKG_ROOT / "sample_data" / "sold_prices.json")


def build_demo_deals(cfg: PipelineConfig | None = None) -> list[Deal]:
    listings = load_listings(_PKG_ROOT / "sample_data" / "demo_listings.json")
    return run_pipeline(listings, load_catalogue(), load_sold_provider(), cfg)
