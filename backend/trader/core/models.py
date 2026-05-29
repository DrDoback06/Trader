"""Domain models shared across the engine (pure data carriers)."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from .economics import EconomicsResult
from .money import Money


class Game(StrEnum):
    POKEMON = "POKEMON"
    LORCANA = "LORCANA"
    ONEPIECE = "ONEPIECE"
    MTG = "MTG"


class BuyingFormat(StrEnum):
    FIXED_PRICE = "FIXED_PRICE"
    AUCTION = "AUCTION"


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
    score: float = 0.0
    passed_rules: bool = False
    rule_reasons: list[str] = field(default_factory=list)

    @property
    def id(self) -> str:
        return f"{self.listing.source}:{self.listing.external_id}"
