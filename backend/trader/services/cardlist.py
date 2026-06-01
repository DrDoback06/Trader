"""A user-managed list of cards to live-search in one go.

Replaces the old whole-category "scour" sweeps: the user curates the exact cards
they care about, and the scan button runs a per-card eBay search for each — the same
keyword-search-and-value-against-the-card flow as the single-card search box, just
batched. Persisted to a local gitignored JSON file so it survives restarts.
"""

from __future__ import annotations

import json
from pathlib import Path


def _clean(query: str) -> str:
    return " ".join(query.split()).strip()


class CardList:
    def __init__(self, queries: list[str], path: Path | None = None) -> None:
        self._path = path
        self._queries: list[str] = []
        for q in queries:  # de-dupe (case-insensitively), preserve order, drop blanks
            self._add_clean(q)

    @classmethod
    def create(cls, path: Path | None, seed: list[str]) -> CardList:
        if path is not None and path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            return cls(list(data.get("cards") or []), path)
        store = cls(seed, path)
        store._persist()
        return store

    def _add_clean(self, query: str) -> bool:
        cleaned = _clean(query)
        if len(cleaned) < 3:
            return False
        if any(cleaned.lower() == existing.lower() for existing in self._queries):
            return False
        self._queries.append(cleaned)
        return True

    def all(self) -> list[str]:
        return list(self._queries)

    def add(self, query: str) -> bool:
        added = self._add_clean(query)
        if added:
            self._persist()
        return added

    def remove(self, query: str) -> bool:
        cleaned = _clean(query).lower()
        before = len(self._queries)
        self._queries = [q for q in self._queries if q.lower() != cleaned]
        removed = len(self._queries) != before
        if removed:
            self._persist()
        return removed

    def set_all(self, queries: list[str]) -> None:
        self._queries = []
        for q in queries:
            self._add_clean(q)
        self._persist()

    def _persist(self) -> None:
        if self._path is None:
            return
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(json.dumps({"cards": self._queries}, indent=2), encoding="utf-8")
