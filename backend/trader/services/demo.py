"""Build a ranked set of demo deals from the bundled sample data (no keys)."""

from __future__ import annotations

from pathlib import Path

from ..core.models import Deal
from ..identify.catalogue import Catalogue
from ..providers.soldprice_fixture import FixtureSoldPriceProvider
from .loaders import load_listings
from .pipeline import PipelineConfig, run_pipeline

_PKG_ROOT = Path(__file__).resolve().parent.parent  # .../trader


def build_demo_deals(cfg: PipelineConfig | None = None) -> list[Deal]:
    catalogue = Catalogue.from_dir(_PKG_ROOT / "catalogue_data")
    sold = FixtureSoldPriceProvider.from_file(_PKG_ROOT / "sample_data" / "sold_prices.json")
    listings = load_listings(_PKG_ROOT / "sample_data" / "demo_listings.json")
    return run_pipeline(listings, catalogue, sold, cfg)
