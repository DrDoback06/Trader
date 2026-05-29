"""Listing de-duplication across a scan.

Primary key is ``(source, external_id)``. A secondary fingerprint over normalised
title + seller + price catches the same card relisted under a new id.
"""

from __future__ import annotations

import hashlib
import re

from ..core.models import ListingFacts

_WS = re.compile(r"\s+")


def fingerprint(listing: ListingFacts) -> str:
    title = _WS.sub(" ", (listing.title or "").lower()).strip()
    seller = (listing.seller or "").lower()
    price = str(listing.price.amount)
    return hashlib.sha1(f"{title}|{seller}|{price}".encode()).hexdigest()


class Dedup:
    def __init__(self) -> None:
        self._ids: set[tuple[str, str]] = set()
        self._fingerprints: set[str] = set()

    def is_new(self, listing: ListingFacts) -> bool:
        key = (listing.source, listing.external_id)
        if key in self._ids:
            return False
        fp = fingerprint(listing)
        if fp in self._fingerprints:
            return False
        self._ids.add(key)
        self._fingerprints.add(fp)
        return True
