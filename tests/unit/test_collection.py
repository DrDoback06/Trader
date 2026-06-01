from __future__ import annotations

from pathlib import Path

from trader.services.collection import Collection, Listing


def test_update_persists_and_reloads(tmp_path: Path) -> None:
    path = tmp_path / "collection.json"
    col = Collection.create(path)
    col.update("POKEMON-MEW-199/165", {"owned": 2, "condition": "NM", "paid": 30.0})
    assert path.exists()

    reloaded = Collection.create(path)
    entry = reloaded.get("POKEMON-MEW-199/165")
    assert entry.owned == 2
    assert entry.condition == "NM"
    assert entry.paid == 30.0


def test_empty_entry_is_pruned(tmp_path: Path) -> None:
    col = Collection.create(tmp_path / "c.json")
    col.update("card-1", {"owned": 1})
    col.update("card-1", {"owned": 0})  # back to empty -> pruned
    assert "card-1" not in col.all()


def test_listings_add_dedupe_remove(tmp_path: Path) -> None:
    col = Collection.create(tmp_path / "c.json")
    col.add_listing("card-1", Listing(url="https://ebay.co.uk/itm/1", item_id="1", source="ebay"))
    col.add_listing("card-1", Listing(url="https://ebay.co.uk/itm/1", item_id="1"))  # dupe
    assert len(col.get("card-1").listings) == 1

    col.add_listing("card-1", Listing(url="https://ebay.co.uk/itm/2"))
    assert len(col.get("card-1").listings) == 2

    col.remove_listing("card-1", "https://ebay.co.uk/itm/1")
    urls = [x.url for x in col.get("card-1").listings]
    assert urls == ["https://ebay.co.uk/itm/2"]


def test_for_sale_and_notes_survive(tmp_path: Path) -> None:
    col = Collection.create(tmp_path / "c.json")
    col.update("card-1", {"for_sale": True, "notes": "selling at a card fair", "target_price": 55})
    entry = col.get("card-1")
    assert entry.for_sale is True
    assert entry.notes == "selling at a card fair"
    assert entry.target_price == 55.0
