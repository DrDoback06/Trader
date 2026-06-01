from __future__ import annotations

from pathlib import Path

from trader.config import Settings
from trader.providers.factory import build_browse_source, build_sold_provider
from trader.services.credentials import CredentialStore
from trader.services.valuation import CachingSoldPriceProvider


def _settings() -> Settings:
    return Settings(_env_file=None)  # type: ignore[call-arg]


def test_sold_provider_defaults_to_fixture(tmp_path: Path) -> None:
    store = CredentialStore.create(_settings(), {"ebay_uk_sold"}, path=tmp_path / "c.json")
    assert build_sold_provider(store, _settings()).name == "fixture"


def test_sold_provider_uses_rapidapi_when_configured(tmp_path: Path) -> None:
    store = CredentialStore.create(_settings(), {"ebay_uk_sold"}, path=tmp_path / "c.json")
    store.set_many({"rapidapi_key": "KEY1234abcd"})
    provider = build_sold_provider(store, _settings())
    assert isinstance(provider, CachingSoldPriceProvider)
    assert provider.name == "ebay_uk_sold"


def test_disabling_sold_source_falls_back_to_fixture(tmp_path: Path) -> None:
    store = CredentialStore.create(_settings(), {"ebay_uk_sold"}, path=tmp_path / "c.json")
    store.set_many({"rapidapi_key": "KEY1234abcd"})
    store.set_enabled("ebay_uk_sold", False)
    assert build_sold_provider(store, _settings()).name == "fixture"


def test_free_market_source_used_when_enabled(tmp_path: Path) -> None:
    # The free pokemontcg.io source needs no key — enabling it alone gives a real
    # (cached) valuation provider instead of the offline fixture.
    store = CredentialStore.create(_settings(), {"pokemontcg_market"}, path=tmp_path / "c.json")
    provider = build_sold_provider(store, _settings())
    assert isinstance(provider, CachingSoldPriceProvider)
    assert provider.name == "pokemontcg_market"


def test_chain_prefers_rapidapi_then_free(tmp_path: Path) -> None:
    # Both enabled + RapidAPI keyed: accurate source first, free source as fallback.
    store = CredentialStore.create(
        _settings(), {"ebay_uk_sold", "pokemontcg_market"}, path=tmp_path / "c.json"
    )
    store.set_many({"rapidapi_key": "KEY1234abcd"})
    provider = build_sold_provider(store, _settings())
    assert isinstance(provider, CachingSoldPriceProvider)
    assert provider.name == "chain"


def test_browse_source_requires_enabled_and_keys(tmp_path: Path) -> None:
    store = CredentialStore.create(_settings(), set(), path=tmp_path / "c.json")
    assert build_browse_source(store, _settings()) is None  # source not enabled

    store.set_enabled("ebay_uk_active", True)
    assert build_browse_source(store, _settings()) is None  # enabled but no keys

    store.set_many({"ebay_client_id": "id", "ebay_client_secret": "sec"})
    assert build_browse_source(store, _settings()) is not None
