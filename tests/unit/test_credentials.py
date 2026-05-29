from __future__ import annotations

from pathlib import Path

from trader.config import Settings
from trader.services.credentials import CredentialStore


def _settings() -> Settings:
    return Settings(_env_file=None)  # type: ignore[call-arg]


def test_set_mask_configured_and_persist(tmp_path: Path) -> None:
    path = tmp_path / "creds.json"
    store = CredentialStore.create(_settings(), {"ebay_uk_active"}, path=path)

    assert store.is_configured("rapidapi_key") is False
    store.set_many({"rapidapi_key": "abcd1234EFGH"})
    assert store.is_configured("rapidapi_key")
    assert store.masked()["rapidapi_key"] == "••••EFGH"
    assert path.exists()

    # A saved file overrides env seeds on reload.
    reloaded = CredentialStore.create(_settings(), {"ebay_uk_active"}, path=path)
    assert reloaded.get("rapidapi_key") == "abcd1234EFGH"


def test_enable_toggle_persists(tmp_path: Path) -> None:
    path = tmp_path / "creds.json"
    store = CredentialStore.create(_settings(), set(), path=path)
    store.set_enabled("ebay_uk_sold", True)

    reloaded = CredentialStore.create(_settings(), set(), path=path)
    assert reloaded.is_enabled("ebay_uk_sold")


def test_short_key_is_masked_without_leaking(tmp_path: Path) -> None:
    store = CredentialStore.create(_settings(), set(), path=tmp_path / "c.json")
    store.set_many({"rapidapi_key": "ab"})
    assert store.masked()["rapidapi_key"] == "set"
