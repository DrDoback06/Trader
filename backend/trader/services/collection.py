"""A local 'what I own' collection, keyed by catalogue card id.

Separate from the Portfolio (which tracks buy-to-flip positions with cost basis and
P&L): this is for collecting — how many of each card you hold, their condition, what
you paid, an optional target sell price + for-sale flag, free-text notes, and the
eBay listings you're selling them through. Persisted to a local gitignored JSON file.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

# Fields a client may set on an entry (everything except the server-managed listings,
# which have their own add/remove endpoints).
_EDITABLE = ("owned", "condition", "paid", "target_price", "for_sale", "notes")


@dataclass
class Listing:
    """One place a card is being sold. ``item_id`` is the eBay item number when known
    (auto-pulled), else it's a manual link the user pasted."""

    url: str
    item_id: str | None = None
    price: float | None = None
    source: str = "manual"  # "manual" | "ebay"


@dataclass
class CardEntry:
    owned: int = 0
    condition: str = ""
    paid: float | None = None  # what you paid (per the quantity you hold)
    target_price: float | None = None  # price you'd sell at
    for_sale: bool = False
    notes: str = ""
    listings: list[Listing] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> CardEntry:
        listings = [
            Listing(
                url=str(item.get("url", "")),
                item_id=item.get("item_id"),
                price=item.get("price"),
                source=str(item.get("source", "manual")),
            )
            for item in (data.get("listings") or [])
            if item.get("url")
        ]
        return cls(
            owned=int(data.get("owned", 0) or 0),
            condition=str(data.get("condition", "") or ""),
            paid=data.get("paid"),
            target_price=data.get("target_price"),
            for_sale=bool(data.get("for_sale", False)),
            notes=str(data.get("notes", "") or ""),
            listings=listings,
        )

    @property
    def is_empty(self) -> bool:
        """An entry with nothing worth persisting (so we can prune it)."""
        return (
            self.owned == 0
            and not self.condition
            and self.paid is None
            and self.target_price is None
            and not self.for_sale
            and not self.notes
            and not self.listings
        )


class Collection:
    def __init__(self, entries: dict[str, CardEntry], path: Path | None = None) -> None:
        self._entries = entries
        self._path = path

    @classmethod
    def create(cls, path: Path | None) -> Collection:
        entries: dict[str, CardEntry] = {}
        if path is not None and path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            for card_id, raw in (data.get("cards") or {}).items():
                entries[card_id] = CardEntry.from_dict(raw)
        return cls(entries, path)

    def all(self) -> dict[str, CardEntry]:
        return dict(self._entries)

    def get(self, card_id: str) -> CardEntry:
        return self._entries.get(card_id, CardEntry())

    def update(self, card_id: str, patch: dict[str, Any]) -> CardEntry:
        entry = self._entries.get(card_id, CardEntry())
        if "owned" in patch and patch["owned"] is not None:
            entry.owned = max(0, int(patch["owned"]))
        if "condition" in patch and patch["condition"] is not None:
            entry.condition = str(patch["condition"]).strip()
        if "paid" in patch:
            entry.paid = _opt_float(patch["paid"])
        if "target_price" in patch:
            entry.target_price = _opt_float(patch["target_price"])
        if "for_sale" in patch and patch["for_sale"] is not None:
            entry.for_sale = bool(patch["for_sale"])
        if "notes" in patch and patch["notes"] is not None:
            entry.notes = str(patch["notes"])
        self._store(card_id, entry)
        return entry

    def add_listing(self, card_id: str, listing: Listing) -> CardEntry:
        entry = self._entries.get(card_id, CardEntry())
        # De-dupe by url (or item_id) so re-importing from eBay doesn't pile up copies.
        key = (listing.item_id or listing.url).lower()
        if not any((x.item_id or x.url).lower() == key for x in entry.listings):
            entry.listings.append(listing)
        self._store(card_id, entry)
        return entry

    def remove_listing(self, card_id: str, url_or_item: str) -> CardEntry:
        entry = self._entries.get(card_id, CardEntry())
        key = url_or_item.lower()
        entry.listings = [
            x
            for x in entry.listings
            if x.url.lower() != key and (x.item_id or "").lower() != key
        ]
        self._store(card_id, entry)
        return entry

    def _store(self, card_id: str, entry: CardEntry) -> None:
        if entry.is_empty:
            self._entries.pop(card_id, None)
        else:
            self._entries[card_id] = entry
        self._persist()

    def _persist(self) -> None:
        if self._path is None:
            return
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"cards": {cid: e.to_dict() for cid, e in self._entries.items()}}
        self._path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _opt_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
