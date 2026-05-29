"""A small default watch list (Pokémon 151 chase cards) for live scanning.

In a later phase these are user-managed and persisted; for now they seed the
``/scan`` endpoint so it does something useful out of the box.
"""

from __future__ import annotations

from ..core.models import Game, WatchTarget

# eBay GB "Pokémon Individual Cards" leaf category.
POKEMON_SINGLES_GB = "183454"


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
