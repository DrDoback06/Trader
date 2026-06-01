from __future__ import annotations

from pathlib import Path

from trader.services.cardlist import CardList


def test_seed_and_persist(tmp_path: Path) -> None:
    path = tmp_path / "cardlist.json"
    cl = CardList.create(path, seed=["Charizard ex 199/165", "Pikachu 173/165"])
    assert cl.all() == ["Charizard ex 199/165", "Pikachu 173/165"]
    assert path.exists()
    # A fresh load reads the persisted file (and ignores the seed).
    assert CardList.create(path, seed=["something else"]).all() == cl.all()


def test_add_dedupes_case_insensitively_and_trims(tmp_path: Path) -> None:
    cl = CardList.create(tmp_path / "c.json", seed=[])
    assert cl.add("  Charizard   ex  199/165 ") is True
    assert cl.all() == ["Charizard ex 199/165"]  # whitespace collapsed
    assert cl.add("charizard EX 199/165") is False  # dupe (case-insensitive)
    assert cl.add("ab") is False  # too short
    assert len(cl.all()) == 1


def test_remove_and_set_all(tmp_path: Path) -> None:
    cl = CardList.create(tmp_path / "c.json", seed=["A card", "B card", "C card"])
    assert cl.remove("b CARD") is True  # case-insensitive remove
    assert cl.all() == ["A card", "C card"]
    cl.set_all(["X card", "X card", "Y card"])  # replace + de-dupe
    assert cl.all() == ["X card", "Y card"]
