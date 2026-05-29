from __future__ import annotations

from trader.services.typos import hidden_gem_queries, misspellings


def test_misspellings_are_plausible_and_capped() -> None:
    variants = misspellings("Charizard", limit=4)
    assert len(variants) == 4
    assert "Charizard" not in variants
    assert all(len(v) >= 4 for v in variants)
    assert len(set(variants)) == len(variants)  # de-duplicated


def test_short_words_are_skipped() -> None:
    assert misspellings("Mew") == []


def test_hidden_gem_queries_combine_typos_and_generic() -> None:
    queries = hidden_gem_queries(
        names=("Charizard",), per_name_typos=2, generic=("pokemon rare holo",)
    )
    assert "pokemon rare holo" in queries
    assert sum(q.startswith("pokemon ") for q in queries) == len(queries)
    assert len(queries) == 3  # 2 typos + 1 generic
