"""Generate misspelled / vague search queries to find listings competitors miss.

Casual sellers underprice and mistype titles; those listings get few eyes, so a
search for the *correct* spelling never surfaces them. We generate plausible
single-edit misspellings of high-value card names plus a few generic low-detail
queries, and scan those.
"""

from __future__ import annotations

DEFAULT_GRAILS: tuple[str, ...] = (
    "Charizard",
    "Pikachu",
    "Umbreon",
    "Lugia",
    "Mewtwo",
    "Blastoise",
    "Rayquaza",
)
DEFAULT_GENERIC: tuple[str, ...] = (
    "pokemon rare holo",
    "pokemon 1st edition holo",
)


def misspellings(word: str, limit: int = 4) -> list[str]:
    """Plausible single-edit typos (interior deletions then transpositions)."""
    w = word.strip()
    if len(w) < 5:
        return []
    out: list[str] = []
    seen: set[str] = set()

    def add(variant: str) -> None:
        key = variant.lower()
        if len(variant) >= 4 and key != w.lower() and key not in seen:
            seen.add(key)
            out.append(variant)

    for i in range(1, len(w) - 1):  # interior deletions (the most common typo)
        add(w[:i] + w[i + 1 :])
    for i in range(1, len(w) - 1):  # interior adjacent transpositions
        add(w[:i] + w[i + 1] + w[i] + w[i + 2 :])
    return out[:limit]


def hidden_gem_queries(
    names: tuple[str, ...] = DEFAULT_GRAILS,
    per_name_typos: int = 3,
    generic: tuple[str, ...] = DEFAULT_GENERIC,
) -> list[str]:
    queries: list[str] = []
    for name in names:
        for variant in misspellings(name, per_name_typos):
            queries.append(f"pokemon {variant}")
    queries.extend(generic)
    return queries
