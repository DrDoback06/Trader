"""Convert domain objects into JSON-friendly dicts for the dashboard."""

from __future__ import annotations

from typing import Any

from ..core.models import Deal
from ..core.money import Money
from ..core.rating import discount_vs_market, profit_tier, sell_tier
from ..core.rules import RuleSet


def money_to_dict(m: Money | None) -> dict[str, Any] | None:
    if m is None:
        return None
    return {"amount": float(m.amount), "currency": m.currency, "display": str(m)}


def deal_to_dict(deal: Deal) -> dict[str, Any]:
    ident = deal.identification
    card = ident.card
    econ = deal.economics
    val = deal.valuation
    grade = None
    if ident.is_graded and ident.grade_company is not None and ident.grade_value is not None:
        gv = int(ident.grade_value) if float(ident.grade_value).is_integer() else ident.grade_value
        grade = f"{ident.grade_company.value} {gv}"

    insights = getattr(deal, "_insights", None) or {}
    return {
        "id": deal.listing.external_id,
        "source": deal.listing.source,
        "passed_rules": deal.passed_rules,
        "score": deal.score,
        "gem_score": getattr(deal, "gem_score", None),
        "active_listings_count": insights.get("active_listings_count"),
        "watchers": insights.get("watchers"),
        "attention_delta_7d": insights.get("attention_delta_7d"),
        "confidence": round(deal.confidence, 3),
        "sell_probability": round(deal.sell_probability, 3),
        "sell_tier": sell_tier(deal.sell_probability).value,
        "profit_tier": profit_tier(econ.roi).value if econ else "RED",
        "discount": round(deal.discount, 4)
        if deal.discount is not None
        else (round(discount_vs_market(econ), 4) if econ else None),
        "hold_candidate": deal.hold_candidate,
        "annualised_roi": (
            round(deal.annualised_roi, 4) if deal.annualised_roi is not None else None
        ),
        "max_bid": money_to_dict(deal.max_bid),
        "trend_pct": round(deal.trend_pct, 4) if deal.trend_pct is not None else None,
        "grading": None
        if deal.grading is None
        else {
            "graded_value": money_to_dict(deal.grading.graded_value),
            "expected_profit": money_to_dict(deal.grading.expected_profit),
            "expected_roi": round(deal.grading.expected_roi, 4),
            "gem_rate": deal.grading.gem_rate,
            "worth_grading": deal.grading.worth_grading,
        },
        "decision": ident.decision.value,
        "match_score": ident.match_score,
        "card": None
        if card is None
        else {
            "id": card.id,
            "name": card.name,
            "set_code": card.set_code,
            "set_name": card.set_name,
            "number": card.number,
            "rarity": card.rarity,
        },
        "is_graded": ident.is_graded,
        "grade": grade,
        "condition": ident.condition_bucket.value,
        "language": ident.parsed.language,
        "flags": ident.parsed.flags,
        "listing": {
            "title": deal.listing.title,
            "price": money_to_dict(deal.listing.price),
            "shipping": money_to_dict(deal.listing.shipping),
            "buying_format": deal.listing.buying_format.value,
            "item_end_date": deal.listing.item_end_date,
            "accepts_best_offer": deal.listing.accepts_best_offer,
            "bid_count": deal.listing.bid_count,
            "current_bid_price": money_to_dict(deal.listing.current_bid_price),
            "url": deal.listing.url,
            "image_url": deal.listing.image_url,
        },
        "valuation": None
        if val is None
        else {
            "median": money_to_dict(val.median),
            "low": money_to_dict(val.low),
            "high": money_to_dict(val.high),
            "sample_size": val.sample_size,
            "spread": round(val.spread, 3),
            "sales_per_week": val.sales_per_week,
            "days_to_sell": val.days_to_sell,
            "provider": val.provider,
        },
        "economics": None
        if econ is None
        else {
            "buy_cost": money_to_dict(econ.buy_cost),
            "est_value": money_to_dict(econ.resale_gross),
            "selling_fees": money_to_dict(econ.selling_fees),
            "net_proceeds": money_to_dict(econ.net_proceeds),
            "profit": money_to_dict(econ.profit),
            "roi": round(econ.roi, 4),
            "margin": round(econ.margin, 4),
        },
        "rule_reasons": deal.rule_reasons,
    }


def ruleset_to_dict(r: RuleSet) -> dict[str, Any]:
    return {
        "total_budget": money_to_dict(r.total_budget),
        "max_spend_per_card": money_to_dict(r.max_spend_per_card),
        "min_profit": money_to_dict(r.min_profit),
        "min_market_value": money_to_dict(r.min_market_value),
        "min_roi": r.min_roi,
        "min_margin": r.min_margin,
        "min_confidence": r.min_confidence,
        "min_sell_probability": r.min_sell_probability,
        "min_annualised_roi": r.min_annualised_roi,
        "min_discount": r.min_discount,
        "graded_policy": r.graded_policy.value,
        "language_whitelist": list(r.language_whitelist),
        "exclude_flags": list(r.exclude_flags),
    }
