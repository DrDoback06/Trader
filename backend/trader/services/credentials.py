"""Runtime credential + source-toggle store.

Lets API keys be entered in the UI and take effect immediately. Values are
seeded from the environment, overridable at runtime, and (optionally) persisted
to a local gitignored JSON file so they survive restarts. Keys are never logged
and are masked when read back.

This is a local, single-user convenience — the file is plaintext, so only use it
on a machine you control.
"""

from __future__ import annotations

import contextlib
import json
from pathlib import Path

from ..config import Settings

SECRET_FIELDS: tuple[str, ...] = (
    "ebay_client_id",
    "ebay_client_secret",
    "rapidapi_key",
    "pricecharting_api_key",
    "anthropic_api_key",
)


def _mask(value: str) -> str | None:
    if not value:
        return None
    return f"••••{value[-4:]}" if len(value) >= 4 else "set"


class CredentialStore:
    def __init__(
        self,
        values: dict[str, str],
        enabled: set[str],
        path: Path | None = None,
    ) -> None:
        self._values: dict[str, str] = {k: values.get(k, "") for k in SECRET_FIELDS}
        self._enabled: set[str] = set(enabled)
        self._path = path

    @classmethod
    def create(
        cls,
        settings: Settings,
        default_enabled: set[str],
        path: Path | None = None,
    ) -> CredentialStore:
        seed = {field: str(getattr(settings, field, "") or "") for field in SECRET_FIELDS}
        store = cls(seed, set(default_enabled), path)
        if path is not None and path.exists():
            store._load()  # a saved file overrides env seeds
        return store

    def get(self, key: str) -> str:
        return self._values.get(key, "")

    def is_configured(self, *keys: str) -> bool:
        return all(self._values.get(k) for k in keys)

    def set_many(self, values: dict[str, str | None]) -> None:
        for key, value in values.items():
            if key in SECRET_FIELDS and value is not None:
                self._values[key] = value.strip()
        self._persist()

    def enabled_sources(self) -> set[str]:
        return set(self._enabled)

    def is_enabled(self, source_id: str) -> bool:
        return source_id in self._enabled

    def set_enabled(self, source_id: str, on: bool) -> None:
        if on:
            self._enabled.add(source_id)
        else:
            self._enabled.discard(source_id)
        self._persist()

    def masked(self) -> dict[str, str | None]:
        return {key: _mask(value) for key, value in self._values.items()}

    def _persist(self) -> None:
        if self._path is None:
            return
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"values": self._values, "enabled": sorted(self._enabled)}
        self._path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        with contextlib.suppress(OSError):  # best effort on non-POSIX
            self._path.chmod(0o600)

    def _load(self) -> None:
        if self._path is None:
            return
        data = json.loads(self._path.read_text(encoding="utf-8"))
        for key, value in (data.get("values") or {}).items():
            if key in SECRET_FIELDS and value:
                self._values[key] = value
        if "enabled" in data:
            self._enabled = set(data["enabled"])
