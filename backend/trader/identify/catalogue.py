"""In-memory card catalogue loaded from JSON, indexed for fast candidate lookup."""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

from ..core.models import Card, Game

_XY = re.compile(r"^(\d{1,3})/(\d{1,3})$")


def canon_number(number: str) -> str:
    """Canonicalise a card number so '058/198' and '58/198' compare equal."""
    n = number.strip().upper().replace(" ", "")
    m = _XY.match(n)
    if m:
        return f"{int(m.group(1))}/{int(m.group(2))}"
    return n


def numerator(number: str) -> int | None:
    m = re.match(r"^(\d{1,3})", canon_number(number))
    return int(m.group(1)) if m else None


class Catalogue:
    def __init__(self, cards: list[Card]) -> None:
        self.cards = cards
        self._by_game: dict[Game, list[Card]] = defaultdict(list)
        self._by_num: dict[tuple[Game, int], list[Card]] = defaultdict(list)
        for c in cards:
            self._by_game[c.game].append(c)
            n = numerator(c.number)
            if n is not None:
                self._by_num[(c.game, n)].append(c)

    def __len__(self) -> int:
        return len(self.cards)

    @classmethod
    def from_dir(cls, path: str | Path) -> Catalogue:
        cards: list[Card] = []
        for fp in sorted(Path(path).rglob("*.json")):
            data = json.loads(fp.read_text(encoding="utf-8"))
            game = Game(data["game"])
            set_code = data["set_code"]
            set_name = data["set_name"]
            for cd in data["cards"]:
                number = canon_number(cd["number"])
                cards.append(
                    Card(
                        id=f"{game.value}-{set_code}-{number}",
                        game=game,
                        set_code=set_code,
                        set_name=set_name,
                        number=number,
                        name=cd["name"],
                        rarity=cd.get("rarity"),
                        finish=cd.get("finish"),
                        language=cd.get("language", "English"),
                        aliases=tuple(cd.get("aliases", [])),
                    )
                )
        return cls(cards)

    def candidates(self, parsed_number: str | None, game: Game = Game.POKEMON) -> list[Card]:
        """Narrow to plausible cards: by card number if we have one, else the game."""
        if parsed_number:
            n = numerator(parsed_number)
            if n is not None and (game, n) in self._by_num:
                return list(self._by_num[(game, n)])
        return list(self._by_game.get(game, []))
