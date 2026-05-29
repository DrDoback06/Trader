"""Confidence scoring for a deal.

Confidence answers "how much do we trust that this is a real, valuable, correctly
identified card priced below market?" — combining identification match quality,
the size and tightness of the sold-price sample, and any soft red flags.

We deliberately bias toward FALSE NEGATIVES (miss a deal) over false positives
(buy a dud): a graded/raw mismatch or a tiny, volatile price sample collapses
confidence quickly.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ConfidenceConfig:
    full_sample_size: int = 8  # sample size at which the sample factor saturates to 1.0
    max_spread: float = 1.0  # spread at/above which the spread factor hits its floor
    spread_floor: float = 0.2  # minimum spread factor (very volatile prices)
    soft_flag_penalty: float = 0.85  # multiplier applied per soft flag


def sample_factor(sample_size: int, cfg: ConfidenceConfig) -> float:
    if cfg.full_sample_size <= 0:
        return 1.0
    return min(1.0, max(0, sample_size) / cfg.full_sample_size)


def spread_factor(spread: float, cfg: ConfidenceConfig) -> float:
    if spread <= 0:
        return 1.0
    fraction = min(1.0, spread / cfg.max_spread)
    return max(cfg.spread_floor, 1.0 - fraction * (1.0 - cfg.spread_floor))


def compute_confidence(
    *,
    match_score: float,
    sample_size: int,
    spread: float,
    soft_flags: int = 0,
    graded_mismatch: bool = False,
    cfg: ConfidenceConfig | None = None,
) -> float:
    """Return a confidence in ``[0, 1]``."""
    cfg = cfg or ConfidenceConfig()
    if graded_mismatch:
        # The valuation is for a different condition class than the listing.
        return 0.0
    base = match_score * sample_factor(sample_size, cfg) * spread_factor(spread, cfg)
    penalty = cfg.soft_flag_penalty ** max(0, soft_flags)
    return max(0.0, min(1.0, base * penalty))
