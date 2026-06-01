"""Tests for the hidden-gem scoring axis.

The gem score is deliberately a different axis to the headline deal score: it
rewards cards with high value AND low attention, so the niche underpriced card
beats the saturated grail even when the grail's absolute profit is bigger.
"""

from __future__ import annotations

import math

from trader.core.scoring import compute_gem_score

# --- guards: bad inputs zero out ---------------------------------------------------

def test_zero_value_means_zero_gem() -> None:
    assert compute_gem_score(
        estimated_value=0.0, confidence=0.9, sell_probability=0.8
    ) == 0.0


def test_zero_confidence_means_zero_gem() -> None:
    assert compute_gem_score(
        estimated_value=100.0, confidence=0.0, sell_probability=0.8
    ) == 0.0


# --- listing saturation ranks niche above mainstream -------------------------------

def test_fewer_active_listings_outranks_saturated_grail() -> None:
    niche = compute_gem_score(
        estimated_value=80.0, confidence=0.9, sell_probability=0.7,
        active_listings=1, sample_size=3,
    )
    mainstream = compute_gem_score(
        estimated_value=150.0, confidence=0.9, sell_probability=0.7,
        active_listings=200, sample_size=30,
    )
    assert niche > mainstream, (niche, mainstream)


def test_more_listings_lowers_gem_strictly() -> None:
    a = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=0, sample_size=0,
    )
    b = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=5, sample_size=0,
    )
    c = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=50, sample_size=0,
    )
    assert a > b > c


# --- trend bonus + clamps ---------------------------------------------------------

def test_positive_trend_bumps_score() -> None:
    flat = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5,
    )
    rising = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5, trend_pct=0.20,
    )
    assert rising > flat
    assert math.isclose(rising / flat, 1.20, rel_tol=0.01)


def test_falling_trend_does_not_penalise() -> None:
    flat = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5,
    )
    falling = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5, trend_pct=-0.30,
    )
    assert falling == flat  # negative trend clamps to 0, no penalty here


# --- liquidity floor: an illiquid niche still ranks -------------------------------

def test_illiquid_niche_still_ranks_due_to_floor() -> None:
    score = compute_gem_score(
        estimated_value=100.0, confidence=0.9, sell_probability=0.0,
        active_listings=1, sample_size=2,
    )
    assert score > 0  # floor of 0.1 on sell_probability keeps a niche listing in the ranking


# --- watcher heavy penalty --------------------------------------------------------

def test_unseen_listing_outranks_heavily_watched_one() -> None:
    quiet = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5, watchers=0,
    )
    busy = compute_gem_score(
        estimated_value=50.0, confidence=0.8, sell_probability=0.6,
        active_listings=2, sample_size=5, watchers=40,
    )
    assert quiet > busy


def test_watchers_floor_at_quarter() -> None:
    huge = compute_gem_score(
        estimated_value=100.0, confidence=0.9, sell_probability=0.7,
        active_listings=0, sample_size=0, watchers=10_000,
    )
    baseline = compute_gem_score(
        estimated_value=100.0, confidence=0.9, sell_probability=0.7,
        active_listings=0, sample_size=0, watchers=0,
    )
    # Floor at 0.25 prevents a heavily-watched listing from collapsing to 0.
    assert math.isclose(huge / baseline, 0.25, rel_tol=0.001)


def test_missing_watchers_is_neutral() -> None:
    a = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4, watchers=None,
    )
    b = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4, watchers=0,
    )
    assert math.isclose(a, b, rel_tol=0.0001)


# --- attention bonus + clamps -----------------------------------------------------

def test_positive_attention_bumps_score_within_clamp() -> None:
    base = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4,
    )
    rising = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4, attention_delta_7d=0.5,
    )
    assert rising > base
    assert math.isclose(rising / base, 1.5, rel_tol=0.01)


def test_huge_attention_spike_is_clamped_at_two_x() -> None:
    base = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4,
    )
    spike = compute_gem_score(
        estimated_value=80.0, confidence=0.8, sell_probability=0.6,
        active_listings=3, sample_size=4, attention_delta_7d=99.0,
    )
    assert math.isclose(spike / base, 2.0, rel_tol=0.01)
