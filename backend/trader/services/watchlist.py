"""A small default watch list (Pokémon 151 chase cards) for live scanning.

In a later phase these are user-managed and persisted; for now they seed the
``/scan`` endpoint so it does something useful out of the box.
"""

from __future__ import annotations

from ..core.models import Game, ScanMode, WatchTarget

# eBay GB "Pokémon Individual Cards" leaf category.
POKEMON_SINGLES_GB = "183454"


def cheapest_sweep_target(
    *, category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,), max_price: float | None = None,
    pages: int = 2, limit: int = 100,
) -> WatchTarget:
    """Scour a whole category for the cheapest Buy-It-Now / Best-Offer listings."""
    return WatchTarget(
        query="",
        mode=ScanMode.CHEAPEST,
        category_ids=category_ids,
        buying_options=("FIXED_PRICE", "BEST_OFFER"),
        sort="price",
        max_price=max_price,
        pages=pages,
        limit=limit,
        priority=4,
    )


def ending_soon_sweep_target(
    *, ending_within_hours: int = 12, category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,),
    max_price: float | None = None, pages: int = 2, limit: int = 100,
) -> WatchTarget:
    """Scour a whole category for auctions ending within the given window."""
    return WatchTarget(
        query="",
        mode=ScanMode.ENDING_SOON,
        category_ids=category_ids,
        buying_options=("AUCTION",),
        ending_within_hours=ending_within_hours,
        sort="endingSoonest",
        max_price=max_price,
        pages=pages,
        limit=limit,
        priority=4,
    )


def default_watchlist() -> list[WatchTarget]:
    return [
        WatchTarget(
            query="Pokemon 151 Charizard ex 199/165",
            game=Game.POKEMON,
            category_ids=(POKEMON_SINGLES_GB,),
            buying_options=("FIXED_PRICE", "AUCTION"),
            max_price=90.0,
            priority=5,
        ),
        WatchTarget(
            query="Pokemon 151 Blastoise ex 201/165",
            game=Game.POKEMON,
            category_ids=(POKEMON_SINGLES_GB,),
            max_price=70.0,
            priority=3,
        ),
        WatchTarget(
            query="Pokemon 151 Pikachu 173/165",
            game=Game.POKEMON,
            category_ids=(POKEMON_SINGLES_GB,),
            max_price=120.0,
            priority=2,
        ),
    ]
