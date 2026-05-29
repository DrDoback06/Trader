"""In-memory card catalogue loaded from JSON, indexed for fast candidate lookup.

Two indexes keep matching fast even with a full ~20k-card catalogue:
- by card-number numerator (used when a listing has a number — the common case),
- by distinctive name token (used for number-less listings, instead of scanning
  every card in the game).
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

from ..core.models import Card, Game

_XY = re.compile(r"^(\d{1,3})/(\d{1,3})$")
_TOKEN = re.compile(r"[a-z0-9]+")

# Common suffixes/words that don't help tell two cards apart.
_NAME_STOPWORDS = {
    "ex", "gx", "v", "vmax", "vstar", "vunion", "prime", "break", "lv", "pokemon", "the", "of",
}
_MAX_NAME_CANDIDATES = 2000


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


def name_tokens(name: str) -> list[str]:
    return [t for t in _TOKEN.findall(name.lower()) if len(t) >= 2 and t not in _NAME_STOPWORDS]


class Catalogue:
    def __init__(self, cards: list[Card]) -> None:
        self.cards = cards
        self.set_meta: dict[str, dict[str, str]] = {}  # set_code -> {"image", "name"}
        self._by_game: dict[Game, list[Card]] = defaultdict(list)
        self._by_num: dict[tuple[Game, int], list[Card]] = defaultdict(list)
        self._by_name_token: dict[tuple[Game, str], list[Card]] = defaultdict(list)
        for c in cards:
            self._by_game[c.game].append(c)
            n = numerator(c.number)
            if n is not None:
                self._by_num[(c.game, n)].append(c)
            for token in name_tokens(c.name):
                self._by_name_token[(c.game, token)].append(c)

    def __len__(self) -> int:
        return len(self.cards)

    @classmethod
    def from_dir(cls, path: str | Path) -> Catalogue:
        cards: list[Card] = []
        set_meta: dict[str, dict[str, str]] = {}
        for fp in sorted(Path(path).rglob("*.json")):
            data = json.loads(fp.read_text(encoding="utf-8"))
            game = Game(data["game"])
            set_code = data["set_code"]
            set_name = data["set_name"]
            set_meta.setdefault(set_code, {"image": data.get("set_image", ""), "name": set_name})
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
                        image_url=cd.get("image", ""),
                    )
                )
        cat = cls(cards)
        cat.set_meta = set_meta
        return cat

    def candidates(
        self,
        parsed_number: str | None,
        parsed_name: str | None = None,
        game: Game = Game.POKEMON,
    ) -> list[Card]:
        """Narrow to plausible cards: by card number if we have one, else by name
        token, else the whole game (last resort)."""
        if parsed_number:
            n = numerator(parsed_number)
            if n is not None and (game, n) in self._by_num:
                return list(self._by_num[(game, n)])

        if parsed_name:
            seen: dict[str, Card] = {}
            for token in name_tokens(parsed_name):
                for card in self._by_name_token.get((game, token), ()):
                    seen.setdefault(card.id, card)
                    if len(seen) >= _MAX_NAME_CANDIDATES:
                        break
            if seen:
                return list(seen.values())

        return list(self._by_game.get(game, []))

    def sets(self, game: Game = Game.POKEMON) -> list[dict[str, object]]:
        """Every set for a game, with its card count and (if imported) a logo image."""
        counts: dict[str, int] = defaultdict(int)
        names: dict[str, str] = {}
        for c in self._by_game.get(game, []):
            counts[c.set_code] += 1
            names.setdefault(c.set_code, c.set_name)
        out: list[dict[str, object]] = [
            {
                "set_code": code,
                "set_name": names[code],
                "count": counts[code],
                "image": self.set_meta.get(code, {}).get("image", ""),
            }
            for code in names
        ]
        return sorted(out, key=lambda s: str(s["set_name"]))

    def cards_in_set(self, set_code: str, game: Game = Game.POKEMON) -> list[Card]:
        """All cards in a set, ordered by collector number."""
        cards = [c for c in self._by_game.get(game, []) if c.set_code == set_code]
        return sorted(cards, key=lambda c: (numerator(c.number) or 9999, c.number))
