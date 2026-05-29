"""The buy/sell rules engine.

Given a scored :class:`Deal` and a :class:`RuleSet`, decide whether it clears the
user's guardrails (budget, per-card cap, minimum profit/ROI/margin, confidence,
graded policy, language, red-flag exclusions, category whitelist) and explain why
if it does not. Sell-side ``limit`` / ``stop_loss`` settings live here too; they
are consumed by the portfolio module in a later phase.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from enum import StrEnum

from .models import Deal
from .money import Money


class GradedPolicy(StrEnum):
    ALLOW = "ALLOW"
    RAW_ONLY = "RAW_ONLY"
    GRADED_ONLY = "GRADED_ONLY"


@dataclass
class RuleSet:
    # --- capital / buy guardrails ---
    total_budget: Money = field(default_factory=lambda: Money(Decimal("300"), "GBP"))
    max_spend_per_card: Money = field(default_factory=lambda: Money(Decimal("60"), "GBP"))
    min_profit: Money = field(default_factory=lambda: Money(Decimal("3"), "GBP"))
    min_roi: float = 0.25
    min_margin: float = 0.15
    min_confidence: float = 0.55
    min_sell_probability: float = 0.0  # off by default; raise to filter illiquid cards
    # --- eligibility ---
    graded_policy: GradedPolicy = GradedPolicy.ALLOW
    language_whitelist: tuple[str, ...] = ("English",)
    exclude_flags: tuple[str, ...] = ("PROXY", "FAKE", "REPRINT", "LOT", "DAMAGED")
    category_whitelist: tuple[str, ...] | None = None
    # --- sell-side (used by the portfolio module later) ---
    default_limit_markup: float = 1.0  # target resale = est_value × markup
    stop_loss_pct: float = 0.80  # floor = cost basis × this fraction
    max_days_held: int = 30


def evaluate(
    deal: Deal,
    rules: RuleSet,
    available_capital: Money | None = None,
) -> tuple[bool, list[str]]:
    """Return ``(passed, reasons)``. ``reasons`` lists every failed guardrail."""
    reasons: list[str] = []
    econ = deal.economics
    if econ is None:
        return False, ["no valuation/economics available"]

    ident = deal.identification

    # --- eligibility ---
    if rules.graded_policy is GradedPolicy.RAW_ONLY and ident.is_graded:
        reasons.append("graded cards excluded by policy")
    if rules.graded_policy is GradedPolicy.GRADED_ONLY and not ident.is_graded:
        reasons.append("raw cards excluded by policy")

    if rules.language_whitelist and ident.parsed.language not in rules.language_whitelist:
        reasons.append(f"language '{ident.parsed.language}' not in whitelist")

    bad_flags = [f for f in ident.parsed.flags if f in rules.exclude_flags]
    if bad_flags:
        reasons.append("excluded flags: " + ", ".join(sorted(set(bad_flags))))

    if rules.category_whitelist and deal.listing.category_id not in rules.category_whitelist:
        reasons.append("category not in whitelist")

    # --- capital / thresholds ---
    if econ.buy_cost > rules.max_spend_per_card:
        reasons.append(f"buy cost {econ.buy_cost} exceeds per-card cap {rules.max_spend_per_card}")

    capital = available_capital if available_capital is not None else rules.total_budget
    if econ.buy_cost > capital:
        reasons.append(f"buy cost {econ.buy_cost} exceeds available capital {capital}")

    if econ.profit < rules.min_profit:
        reasons.append(f"profit {econ.profit} below minimum {rules.min_profit}")
    if econ.roi < rules.min_roi:
        reasons.append(f"ROI {econ.roi:.0%} below minimum {rules.min_roi:.0%}")
    if econ.margin < rules.min_margin:
        reasons.append(f"margin {econ.margin:.0%} below minimum {rules.min_margin:.0%}")
    if deal.confidence < rules.min_confidence:
        reasons.append(f"confidence {deal.confidence:.2f} below minimum {rules.min_confidence:.2f}")
    if deal.sell_probability < rules.min_sell_probability:
        reasons.append(
            f"sell-through {deal.sell_probability:.0%} below minimum "
            f"{rules.min_sell_probability:.0%}"
        )

    return (len(reasons) == 0, reasons)
