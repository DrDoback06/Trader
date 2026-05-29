"""The core pipeline: listing -> identify -> value -> economics -> score -> rules.

Pure orchestration over injected providers, so it runs identically on offline
fixtures (Phase 1) and on live data (Phases 2-3).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from ..core.confidence import ConfidenceConfig, compute_confidence
from ..core.economics import (
    FeeProfile,
    GradingProfile,
    compute_economics,
    compute_grading_economics,
    max_bid_for_target,
)
from ..core.models import BuyingFormat, Deal, Decision, Game, ListingFacts
from ..core.rating import RatingConfig, annualised_roi
from ..core.rating import sell_probability as compute_sell_probability
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
    rating: RatingConfig = field(default_factory=RatingConfig)
    grading: GradingProfile = field(default_factory=GradingProfile.default_uk)
    evaluate_grading: bool = True
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

    # For auctions, the price you'd pay right now is the current bid, not the BIN.
    is_auction = listing.buying_format is BuyingFormat.AUCTION
    effective_ask = (
        listing.current_bid_price
        if is_auction and listing.current_bid_price is not None
        else listing.price
    )

    deal.economics = compute_economics(
        ask_price=effective_ask,
        est_value=valuation.median,
        fee_profile=cfg.fee_profile,
        inbound_postage=listing.shipping,
    )
    deal.max_bid = max_bid_for_target(
        est_value=valuation.median,
        fee_profile=cfg.fee_profile,
        min_roi=cfg.rules.min_roi,
        min_profit=cfg.rules.min_profit,
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
    deal.sell_probability = compute_sell_probability(
        valuation.sample_size,
        valuation.spread,
        target_ratio=cfg.rules.default_limit_markup,
        sales_per_week=valuation.sales_per_week,
        cfg=cfg.rating,
    )
    deal.annualised_roi = annualised_roi(deal.economics.roi, valuation.days_to_sell)

    # Grade-and-flip: for a raw card, is it worth grading and selling as a slab?
    if cfg.evaluate_grading and not ident.is_graded:
        graded = sold_provider.get_valuation(ident.card, cfg.grading.graded_key)
        if graded is not None:
            deal.grading = compute_grading_economics(
                raw_buy_cost=deal.economics.buy_cost,
                graded_value=graded.median,
                fee_profile=cfg.fee_profile,
                grading_profile=cfg.grading,
            )

    deal.score = deal_score(deal.economics, deal.confidence, deal.sell_probability)

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
