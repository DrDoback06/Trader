"""Normalise a free-text condition into a raw :class:`ConditionBucket`.

Conservative on purpose: when there is no condition signal at all we assume
Lightly Played (not Near Mint), so we under- rather than over-value, which biases
the engine toward missing a deal rather than buying a dud.
"""

from __future__ import annotations

import re

from ..core.models import ConditionBucket

_DAMAGED = re.compile(r"\b(damaged|creased?|bent|water\s?damage|poor)\b", re.I)
_HEAVY = re.compile(r"\b(heavily\s?played|heavy\s?play)\b", re.I)
_MODERATE = re.compile(r"\b(moderately\s?played|moderate\s?play|\bmp\b|played|good)\b", re.I)
_LIGHT = re.compile(r"\b(lightly\s?played|light\s?play|\blp\b|excellent)\b", re.I)
_MINT = re.compile(r"\b(near\s?mint|\bnm\b|mint|brand\s?new|\bnew\b|gem)\b", re.I)


def normalize_condition(condition_raw: str | None, title: str = "") -> ConditionBucket:
    text = " ".join(x for x in [condition_raw, title] if x)
    if not text:
        return ConditionBucket.RAW_LP
    if _DAMAGED.search(text):
        return ConditionBucket.RAW_DAMAGED
    if _HEAVY.search(text):
        return ConditionBucket.RAW_HP
    if _MODERATE.search(text):
        return ConditionBucket.RAW_MP
    if _LIGHT.search(text):
        return ConditionBucket.RAW_LP
    if _MINT.search(text):
        return ConditionBucket.RAW_NM
    if re.search(r"\bused\b", text, re.I):
        return ConditionBucket.RAW_LP
    return ConditionBucket.RAW_LP
