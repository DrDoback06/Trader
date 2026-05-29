"""Convert domain objects into JSON-friendly dicts for the dashboard."""

from __future__ import annotations

from typing import Any

from ..core.models import Deal
from ..core.money import Money
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

    return {
        "id": deal.listing.external_id,
        "source": deal.listing.source,
        "passed_rules": deal.passed_rules,
        "score": deal.score,
        "confidence": round(deal.confidence, 3),
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
        "min_roi": r.min_roi,
        "min_margin": r.min_margin,
        "min_confidence": r.min_confidence,
        "graded_policy": r.graded_policy.value,
        "language_whitelist": list(r.language_whitelist),
        "exclude_flags": list(r.exclude_flags),
    }
