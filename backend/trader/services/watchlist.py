"""A small default watch list (Pokémon 151 chase cards) for live scanning.

In a later phase these are user-managed and persisted; for now they seed the
``/scan`` endpoint so it does something useful out of the box.
"""

from __future__ import annotations

from ..core.models import Game, ScanMode, WatchTarget
from .typos import hidden_gem_queries

# eBay GB "Pokémon Individual Cards" leaf category.
POKEMON_SINGLES_GB = "183454"

# Category/grade sweeps sort by price ascending, so without a floor they'd return
# nothing but £0.01 bulk commons. Skip anything cheaper than this on a sweep.
BULK_FLOOR_GBP = 4.0


def cheapest_sweep_target(
    *, category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,), max_price: float | None = None,
    min_price: float | None = BULK_FLOOR_GBP, pages: int = 2, limit: int = 100,
) -> WatchTarget:
    """Scour a whole category for the cheapest Buy-It-Now / Best-Offer listings."""
    return WatchTarget(
        query="",
        mode=ScanMode.CHEAPEST,
        category_ids=category_ids,
        buying_options=("FIXED_PRICE", "BEST_OFFER"),
        sort="price",
        max_price=max_price,
        min_price=min_price,
        pages=pages,
        limit=limit,
        priority=4,
    )


def ending_soon_sweep_target(
    *, ending_within_hours: int = 12, category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,),
    max_price: float | None = None, min_price: float | None = BULK_FLOOR_GBP,
    pages: int = 2, limit: int = 100,
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
        min_price=min_price,
        pages=pages,
        limit=limit,
        priority=4,
    )


# Grades worth sweeping: 10 for flips, 7/8/9 for value holds, 1 for cheap oddity holds.
DEFAULT_GRADERS: tuple[str, ...] = ("PSA", "CGC")
DEFAULT_GRADES: tuple[int, ...] = (10, 9, 8, 7, 1)


def graded_sweep_targets(
    *, graders: tuple[str, ...] = DEFAULT_GRADERS, grades: tuple[int, ...] = DEFAULT_GRADES,
    category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,), max_price: float | None = None,
    limit: int = 100,
) -> list[WatchTarget]:
    """Sweep slabbed cards across graders × grades — each valued against its own
    grade's sold prices. The whole-grade sweep covers every card, not just grails."""
    return [
        WatchTarget(
            query=f"pokemon {grader} {grade}",
            game=Game.POKEMON,
            category_ids=category_ids,
            buying_options=("FIXED_PRICE", "BEST_OFFER", "AUCTION"),
            sort="price",
            max_price=max_price,
            min_price=BULK_FLOOR_GBP,  # a £0.01 "PSA 10" hit is junk, not a slab
            limit=limit,
            priority=3,
        )
        for grader in graders
        for grade in grades
    ]


def sealed_sweep_targets(
    *, max_price: float | None = None, limit: int = 100
) -> list[WatchTarget]:
    """Sweep for sealed product (boxes / ETBs / bundles). Valued catalogue-free."""
    queries = (
        "pokemon booster box",
        "pokemon elite trainer box",
        "pokemon booster bundle",
        "pokemon 151 booster box",
    )
    return [
        WatchTarget(
            query=q,
            game=Game.POKEMON,
            buying_options=("FIXED_PRICE", "BEST_OFFER"),
            sort="price",
            max_price=max_price,
            limit=limit,
            priority=3,
        )
        for q in queries
    ]


def hidden_gem_targets(
    *, category_ids: tuple[str, ...] = (POKEMON_SINGLES_GB,), max_price: float | None = None,
    limit: int = 50,
) -> list[WatchTarget]:
    """Search misspelled / vague queries for high-value cards competitors miss."""
    return [
        WatchTarget(
            query=q,
            game=Game.POKEMON,
            category_ids=category_ids,
            buying_options=("FIXED_PRICE", "BEST_OFFER"),
            sort="newlyListed",
            max_price=max_price,
            limit=limit,
            priority=2,
        )
        for q in hidden_gem_queries()
    ]


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
