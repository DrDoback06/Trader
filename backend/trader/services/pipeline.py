"""The core pipeline: listing -> identify -> value -> economics -> score -> rules.

Pure orchestration over injected providers, so it runs identically on offline
fixtures (Phase 1) and on live data (Phases 2-3).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from ..core.confidence import ConfidenceConfig, compute_confidence
from ..core.economics import FeeProfile, compute_economics
from ..core.models import Deal, Decision, Game, ListingFacts
from ..core.rules import RuleSet, evaluate
from ..core.scoring import deal_score, rank_deals
from ..identify.catalogue import Catalogue
from ..identify.matcher import MatcherConfig, identify
from ..identify.normalize import normalize_condition
from ..identify.parser import parse_listing
from ..providers.base import SoldPriceProvider


@dataclass
class PipelineConfig:
    fee_profile: FeeProfile = field(default_factory=FeeProfile.default_uk)
    rules: RuleSet = field(default_factory=RuleSet)
    matcher: MatcherConfig = field(default_factory=MatcherConfig)
    confidence: ConfidenceConfig = field(default_factory=ConfidenceConfig)
    game: Game = Game.POKEMON


def evaluate_listing(
    listing: ListingFacts,
    catalogue: Catalogue,
    sold_provider: SoldPriceProvider,
    cfg: PipelineConfig,
) -> Deal:
    parsed = parse_listing(listing.title, listing.item_specifics)
    bucket = normalize_condition(listing.condition_raw, listing.title)
    ident = identify(parsed, catalogue, bucket, game=cfg.game, cfg=cfg.matcher)

    deal = Deal(listing=listing, identification=ident)

    if ident.decision is Decision.REJECTED or ident.card is None:
        deal.rule_reasons = [f"identification: {ident.decision.value}"]
        return deal

    valuation = sold_provider.get_valuation(ident.card, ident.valuation_key)
    if valuation is None:
        deal.rule_reasons = [f"no sold-price data for {ident.card.id} [{ident.valuation_key}]"]
        return deal
    deal.valuation = valuation

    deal.economics = compute_economics(
        ask_price=listing.price,
        est_value=valuation.median,
        fee_profile=cfg.fee_profile,
        inbound_postage=listing.shipping,
    )

    soft_flags = sum(1 for f in parsed.flags if f not in cfg.matcher.hard_flags)
    deal.confidence = compute_confidence(
        match_score=ident.match_score,
        sample_size=valuation.sample_size,
        spread=valuation.spread,
        soft_flags=soft_flags,
        cfg=cfg.confidence,
    )
    deal.score = deal_score(deal.economics, deal.confidence)

    passed, reasons = evaluate(deal, cfg.rules)
    deal.passed_rules = passed
    deal.rule_reasons = reasons
    return deal


def run_pipeline(
    listings: list[ListingFacts],
    catalogue: Catalogue,
    sold_provider: SoldPriceProvider,
    cfg: PipelineConfig | None = None,
) -> list[Deal]:
    cfg = cfg or PipelineConfig()
    deals = [evaluate_listing(listing, catalogue, sold_provider, cfg) for listing in listings]
    return rank_deals(deals)
