"""Match a :class:`ParsedListing` to a catalogue :class:`Card`.

Conservative by design. A hard red flag (proxy/fake/lot) is an immediate REJECT
regardless of name similarity. When the top two candidates are too close, we mark
AMBIGUOUS rather than guess. The combined ``match_score`` weights name similarity,
card-number agreement, and set agreement.
"""

from __future__ import annotations

from dataclasses import dataclass

from ..core.models import (
    Card,
    ConditionBucket,
    Decision,
    Game,
    Identification,
    ParsedListing,
)
from ._fuzzy import token_ratio
from .catalogue import Catalogue, canon_number, numerator


@dataclass(frozen=True)
class MatcherConfig:
    match_threshold: float = 0.60  # below this => REJECTED (can't value safely)
    ambiguous_margin: float = 0.08  # top-2 closer than this => AMBIGUOUS
    name_weight: float = 0.55
    number_weight: float = 0.35
    set_weight: float = 0.10
    hard_flags: tuple[str, ...] = ("PROXY", "FAKE", "LOT")


def _norm(s: str) -> str:
    return " ".join(s.lower().split())


def _number_signal(parsed: ParsedListing, card: Card) -> float:
    if not parsed.number:
        return 0.5  # unknown — neutral
    pc, cc = canon_number(parsed.number), canon_number(card.number)
    if pc == cc:
        return 1.0
    pn, cn = numerator(pc), numerator(cc)
    if pn is not None and pn == cn:
        return 0.85  # same collector number, different total (set variation)
    return 0.0


def _set_signal(parsed: ParsedListing, card: Card) -> float:
    if not parsed.set_code:
        return 0.5  # unknown — neutral
    return 1.0 if parsed.set_code.upper() == card.set_code.upper() else 0.0


def score_card(parsed: ParsedListing, card: Card, cfg: MatcherConfig) -> float:
    candidates = [card.name, *card.aliases]
    name_sim = (
        max(token_ratio(_norm(parsed.name), _norm(n)) for n in candidates) if parsed.name else 0.0
    )
    return (
        cfg.name_weight * name_sim
        + cfg.number_weight * _number_signal(parsed, card)
        + cfg.set_weight * _set_signal(parsed, card)
    )


def identify(
    parsed: ParsedListing,
    catalogue: Catalogue,
    condition_bucket: ConditionBucket,
    *,
    game: Game = Game.POKEMON,
    cfg: MatcherConfig | None = None,
) -> Identification:
    cfg = cfg or MatcherConfig()
    result = Identification(
        parsed=parsed,
        decision=Decision.REJECTED,
        match_score=0.0,
        condition_bucket=ConditionBucket.GRADED if parsed.is_graded else condition_bucket,
        is_graded=parsed.is_graded,
        grade_company=parsed.grade_company,
        grade_value=parsed.grade_value,
    )

    if any(f in cfg.hard_flags for f in parsed.flags):
        return result  # hard reject

    candidates = catalogue.candidates(parsed.number, game)
    if not candidates:
        return result

    scored = sorted(
        ((c, score_card(parsed, c, cfg)) for c in candidates),
        key=lambda x: x[1],
        reverse=True,
    )
    best_card, best_score = scored[0]
    second_score = scored[1][1] if len(scored) > 1 else 0.0
    result.match_score = round(best_score, 4)

    if best_score < cfg.match_threshold:
        return result  # not confident enough to value

    too_close = (best_score - second_score) < cfg.ambiguous_margin
    if len(scored) > 1 and scored[1][0].id != best_card.id and too_close:
        result.decision = Decision.AMBIGUOUS
        result.card = best_card
        return result

    result.decision = Decision.MATCHED
    result.card = best_card
    return result
