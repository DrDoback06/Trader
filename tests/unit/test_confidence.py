from __future__ import annotations

import pytest

from trader.core.confidence import (
    ConfidenceConfig,
    compute_confidence,
    sample_factor,
    spread_factor,
)


def test_sample_factor_saturates() -> None:
    cfg = ConfidenceConfig(full_sample_size=8)
    assert sample_factor(0, cfg) == 0.0
    assert sample_factor(4, cfg) == 0.5
    assert sample_factor(8, cfg) == 1.0
    assert sample_factor(50, cfg) == 1.0


def test_spread_factor_decreases_with_volatility() -> None:
    cfg = ConfidenceConfig(max_spread=1.0, spread_floor=0.2)
    assert spread_factor(0.0, cfg) == 1.0
    assert spread_factor(1.0, cfg) == pytest.approx(0.2)
    assert spread_factor(5.0, cfg) == pytest.approx(0.2)  # clamped at floor
    assert spread_factor(0.25, cfg) > spread_factor(0.75, cfg)


def test_graded_mismatch_collapses_confidence() -> None:
    c = compute_confidence(match_score=1.0, sample_size=50, spread=0.0, graded_mismatch=True)
    assert c == 0.0


def test_soft_flags_reduce_confidence() -> None:
    base = compute_confidence(match_score=1.0, sample_size=50, spread=0.0, soft_flags=0)
    one = compute_confidence(match_score=1.0, sample_size=50, spread=0.0, soft_flags=1)
    two = compute_confidence(match_score=1.0, sample_size=50, spread=0.0, soft_flags=2)
    assert base > one > two


def test_confidence_is_bounded() -> None:
    c = compute_confidence(match_score=1.0, sample_size=999, spread=0.0)
    assert 0.0 <= c <= 1.0
    assert c == pytest.approx(1.0)
