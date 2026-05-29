"""Domain models shared across the engine (pure data carriers)."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from .economics import EconomicsResult, GradingResult
from .money import Money


class Game(StrEnum):
    POKEMON = "POKEMON"
    LORCANA = "LORCANA"
    ONEPIECE = "ONEPIECE"
    MTG = "MTG"


class BuyingFormat(StrEnum):
    FIXED_PRICE = "FIXED_PRICE"
    AUCTION = "AUCTION"


class ScanMode(StrEnum):
    WATCH = "WATCH"  # search specific card queries (the watchlist)
    CHEAPEST = "CHEAPEST"  # sweep a category for cheapest BIN / Best-Offer
    ENDING_SOON = "ENDING_SOON"  # auctions ending within a time window


class GradeCompany(StrEnum):
    PSA = "PSA"
    CGC = "CGC"
    BGS = "BGS"
    SGC = "SGC"
    ACE = "ACE"


class ConditionBucket(StrEnum):
    RAW_NM = "RAW_NM"  # Near Mint / Mint
    RAW_LP = "RAW_LP"  # Lightly Played / Excellent
    RAW_MP = "RAW_MP"  # Moderately Played / Good
    RAW_HP = "RAW_HP"  # Heavily Played
    RAW_DAMAGED = "RAW_DAMAGED"
    GRADED = "GRADED"


class Decision(StrEnum):
    MATCHED = "MATCHED"
    AMBIGUOUS = "AMBIGUOUS"
    REJECTED = "REJECTED"


def _fmt_grade(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else str(value)


@dataclass(frozen=True)
class Card:
    """A catalogue entry — one printing of one card."""

    id: str
    game: Game
    set_code: str
    set_name: str
    number: str
    name: str
    rarity: str | None = None
    finish: str | None = None
    language: str = "English"
    aliases: tuple[str, ...] = ()


@dataclass
class ParsedListing:
    """What we extracted from a listing's title / item specifics."""

    name: str
    set_code: str | None = None
    set_name: str | None = None
    number: str | None = None
    finish: str | None = None
    language: str = "English"
    is_graded: bool = False
    grade_company: GradeCompany | None = None
    grade_value: float | None = None
    flags: list[str] = field(default_factory=list)


@dataclass
class WatchTarget:
    """A search the scanner runs against a listing source.

    ``mode`` decides how it searches: a specific card query (WATCH), a whole-category
    sweep for the cheapest BIN/Best-Offer listings (CHEAPEST), or auctions ending
    within ``ending_within_hours`` (ENDING_SOON). Higher priority = scanned first
    when the daily call budget is tight.
    """

    query: str = ""
    game: Game = Game.POKEMON
    mode: ScanMode = ScanMode.WATCH
    category_ids: tuple[str, ...] = ()
    buying_options: tuple[str, ...] = ("FIXED_PRICE",)
    max_price: float | None = None
    condition_ids: tuple[str, ...] = ()
    ending_within_hours: int | None = None
    sort: str | None = None
    pages: int = 1
    priority: int = 1
    limit: int = 50
    enabled: bool = True


@dataclass
class ListingFacts:
    """Normalised facts about a single marketplace listing (engine input)."""

    external_id: str
    title: str
    price: Money
    source: str = "EBAY"
    shipping: Money | None = None
    item_specifics: dict[str, str] = field(default_factory=dict)
    buying_format: BuyingFormat = BuyingFormat.FIXED_PRICE
    condition_raw: str | None = None
    seller: str | None = None
    item_location_country: str = "GB"
    category_id: str | None = None
    url: str | None = None
    image_url: str | None = None
    item_end_date: str | None = None  # auction end time (UTC ISO8601), if any
    accepts_best_offer: bool = False
    bid_count: int | None = None  # auctions only
    current_bid_price: Money | None = None  # auctions only


@dataclass
class Identification:
    """The result of identifying a listing against the catalogue."""

    parsed: ParsedListing
    decision: Decision
    match_score: float
    card: Card | None = None
    condition_bucket: ConditionBucket = ConditionBucket.RAW_NM
    is_graded: bool = False
    grade_company: GradeCompany | None = None
    grade_value: float | None = None

    @property
    def valuation_key(self) -> str:
        """Key under which sold prices are bucketed for this card+condition."""
        if self.is_graded and self.grade_company is not None and self.grade_value is not None:
            return f"GRADED_{self.grade_company.value}_{_fmt_grade(self.grade_value)}"
        return self.condition_bucket.value


@dataclass
class Valuation:
    """Estimated market value for a card in a given condition bucket."""

    card_id: str
    condition_key: str
    provider: str
    median: Money
    average: Money | None = None
    low: Money | None = None
    high: Money | None = None
    sample_size: int = 0
    spread: float = 0.0  # (high - low) / median; widens => less confidence
    sales_per_week: float | None = None  # observed sold velocity, if known
    days_to_sell: float | None = None  # estimated days to sell at market
    currency: str = "GBP"


@dataclass
class Deal:
    """A scored, rule-checked opportunity for one listing."""

    listing: ListingFacts
    identification: Identification
    valuation: Valuation | None = None
    economics: EconomicsResult | None = None
    confidence: float = 0.0
    sell_probability: float = 0.0
    annualised_roi: float | None = None
    max_bid: Money | None = None  # most to pay (bid/offer) and still hit targets
    grading: GradingResult | None = None  # raw -> slab grade-and-flip economics
    score: float = 0.0
    passed_rules: bool = False
    rule_reasons: list[str] = field(default_factory=list)

    @property
    def id(self) -> str:
        return f"{self.listing.source}:{self.listing.external_id}"
