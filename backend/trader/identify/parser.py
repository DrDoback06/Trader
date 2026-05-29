"""Parse an eBay listing (title + item specifics) into a :class:`ParsedListing`.

This extracts the card *identity* (name, set, number, finish, language, grade) and
attaches red-flag markers. It is deliberately decoupled from the catalogue — the
matcher does the catalogue lookup.
"""

from __future__ import annotations

import re

from ..core.models import GradeCompany, ParsedListing
from .grading import GRADE_RE, detect_grade

# --- card number ---
_NUM_XY = re.compile(r"(\d{1,3})\s*/\s*(\d{1,3})")
_NUM_PROMO = re.compile(
    r"\b(SWSH\d{1,3}|SVP\d{1,3}|SV\d{1,3}|XY\d{1,3}|GG\d{1,2}|TG\d{1,2})\b", re.I
)

# --- set synonyms (seed sets only; grows with the catalogue) ---
_SET_SYNONYMS: dict[str, str] = {
    "151": "MEW",
    "mew": "MEW",
    "scarlet & violet 151": "MEW",
    "scarlet and violet 151": "MEW",
    "obsidian flames": "OBF",
    "obf": "OBF",
    "base set": "BS",
}

# --- finishes (order matters: specific before generic) ---
_FINISHES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\breverse\s?holo\b", re.I), "Reverse Holo"),
    (re.compile(r"\bfull\s?art\b", re.I), "Full Art"),
    (re.compile(r"\balt(ernate)?\s?art\b", re.I), "Alt Art"),
    (re.compile(r"\b1st\s?edition\b", re.I), "1st Edition"),
    (re.compile(r"\bshadowless\b", re.I), "Shadowless"),
    (re.compile(r"\bholo(graphic|foil)?\b", re.I), "Holo"),
]

# --- languages ---
_LANGUAGES: list[tuple[str, re.Pattern[str]]] = [
    ("Japanese", re.compile(r"\b(japanese|japan|jpn|\bjp\b)\b", re.I)),
    ("German", re.compile(r"\b(german|deutsch)\b", re.I)),
    ("French", re.compile(r"\b(french|francais|français)\b", re.I)),
    ("Italian", re.compile(r"\bitalian\b", re.I)),
    ("Spanish", re.compile(r"\b(spanish|espanol|español)\b", re.I)),
    ("Korean", re.compile(r"\b(korean|korea)\b", re.I)),
    ("Chinese", re.compile(r"\b(chinese|china)\b", re.I)),
]

# --- red flags ---
_FLAGS: dict[str, re.Pattern[str]] = {
    "PROXY": re.compile(r"\b(proxy|proxies|orica)\b", re.I),
    "FAKE": re.compile(r"\b(fake|counterfeit|repro|reproduction)\b", re.I),
    "REPRINT": re.compile(r"\breprints?\b", re.I),
    "LOT": re.compile(
        r"\b(lot|joblot|job\s?lot|bundle|bulk|playset)\b|\bx\s?\d{2,}\b|\b\d{2,}\s?cards?\b", re.I
    ),
    "DAMAGED": re.compile(
        r"\b(damaged|creased?|bent|water\s?damage|poor\s?condition|heavily\s?played)\b", re.I
    ),
}

# words stripped when deriving a card name from a title
_NAME_NOISE = {
    "pokemon", "pokémon", "tcg", "ccg", "card", "cards", "single", "genuine", "official",
    "mint", "near", "nm", "lp", "mp", "hp", "played", "lightly", "heavily", "moderately",
    "light", "heavy", "condition", "holo", "holographic", "foil", "reverse", "full", "art",
    "alt", "alternate", "edition", "1st", "shadowless", "rare", "ultra", "secret", "rainbow",
    "english", "japanese", "new", "brand", "fresh", "uk", "psa", "cgc", "bgs", "sgc", "ace",
    "graded", "grade", "gem", "the", "of", "set", "number", "no", "sir", "ir", "ar",
    "obsidian", "flames", "base", "151",
}


def _extract_number(text: str, specifics: dict[str, str]) -> str | None:
    raw = specifics.get("Card Number") or specifics.get("Card number") or ""
    for source in (raw, text):
        if not source:
            continue
        m = _NUM_XY.search(source)
        if m:
            return f"{int(m.group(1))}/{int(m.group(2))}"
        m = _NUM_PROMO.search(source)
        if m:
            return m.group(1).upper()
    return None


def _extract_set(text: str, specifics: dict[str, str]) -> tuple[str | None, str | None]:
    raw = (specifics.get("Set") or "").strip()
    if raw and raw.lower() in _SET_SYNONYMS:
        return _SET_SYNONYMS[raw.lower()], raw
    low = text.lower()
    for syn, code in _SET_SYNONYMS.items():
        if len(syn) >= 4 and syn in low:
            return code, syn
    if re.search(r"\b151\b", text):
        return "MEW", "151"
    return None, (raw or None)


def _extract_finish(text: str, specifics: dict[str, str]) -> str | None:
    hay = " ".join(x for x in [specifics.get("Features"), specifics.get("Finish"), text] if x)
    for pat, val in _FINISHES:
        if pat.search(hay):
            return val
    return None


def _extract_language(text: str, specifics: dict[str, str]) -> str:
    raw = specifics.get("Language")
    if raw:
        for lang, _ in _LANGUAGES:
            if lang.lower() in raw.lower():
                return lang
        return "English"
    for lang, pat in _LANGUAGES:
        if pat.search(text):
            return lang
    return "English"


def _extract_grade(
    text: str, specifics: dict[str, str]
) -> tuple[bool, GradeCompany | None, float | None]:
    grader = specifics.get("Professional Grader") or specifics.get("Grading Company")
    grade = specifics.get("Grade")
    if grader and grade:
        try:
            company = GradeCompany(grader.strip().upper())
            value = float(re.sub(r"[^0-9.]", "", grade))
            return True, company, value
        except (ValueError, KeyError):
            pass
    return detect_grade(text)


def detect_flags(text: str, specifics: dict[str, str]) -> list[str]:
    hay = " ".join([text, *specifics.values()])
    return [flag for flag, pat in _FLAGS.items() if pat.search(hay)]


def _extract_name(text: str, specifics: dict[str, str]) -> str:
    explicit = specifics.get("Card Name")
    if explicit:
        return explicit.strip()
    s = _NUM_XY.sub(" ", text)
    s = _NUM_PROMO.sub(" ", s)
    s = GRADE_RE.sub(" ", s)
    tokens = [t for t in re.split(r"[^A-Za-z0-9&]+", s) if t and t.lower() not in _NAME_NOISE]
    return " ".join(tokens).strip()


def parse_listing(title: str, item_specifics: dict[str, str] | None = None) -> ParsedListing:
    specifics = item_specifics or {}
    text = title or ""
    set_code, set_name = _extract_set(text, specifics)
    is_graded, grade_company, grade_value = _extract_grade(text, specifics)
    return ParsedListing(
        name=_extract_name(text, specifics),
        set_code=set_code,
        set_name=set_name,
        number=_extract_number(text, specifics),
        finish=_extract_finish(text, specifics),
        language=_extract_language(text, specifics),
        is_graded=is_graded,
        grade_company=grade_company,
        grade_value=grade_value,
        flags=detect_flags(text, specifics),
    )
