"""Detect professional grading (PSA / CGC / BGS / SGC / ACE) and grade value."""

from __future__ import annotations

import re

from ..core.models import GradeCompany

# e.g. "PSA 10", "CGC 9.5", "BGS9", "SGC 8.5"
GRADE_RE = re.compile(
    r"\b(PSA|BGS|CGC|SGC|ACE)\b\s*[-:]?\s*(10|[0-9](?:\.5)?)\b",
    re.IGNORECASE,
)


def detect_grade(text: str) -> tuple[bool, GradeCompany | None, float | None]:
    if not text:
        return (False, None, None)
    m = GRADE_RE.search(text)
    if not m:
        return (False, None, None)
    try:
        company = GradeCompany(m.group(1).upper())
    except ValueError:  # pragma: no cover
        return (False, None, None)
    return (True, company, float(m.group(2)))
