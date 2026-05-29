"""Fuzzy string ratio. Uses rapidfuzz when present, else a stdlib fallback so the
pure core stays importable with zero third-party dependencies."""

from __future__ import annotations

try:
    from rapidfuzz import fuzz

    def token_ratio(a: str, b: str) -> float:
        return float(fuzz.token_set_ratio(a, b)) / 100.0

except ImportError:  # pragma: no cover - exercised only without rapidfuzz
    import difflib

    def token_ratio(a: str, b: str) -> float:
        return difflib.SequenceMatcher(None, a, b).ratio()
