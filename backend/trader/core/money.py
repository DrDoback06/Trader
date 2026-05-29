"""A small ``Money`` value object.

Money is always represented with ``Decimal`` (never ``float``) and an explicit
currency, so that GBP/USD can never be silently mixed — any cross-currency
operation must go through :meth:`Money.convert` with an explicit FX rate.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

TWO_PLACES = Decimal("0.01")
Numeric = int | float | str | Decimal

_SYMBOLS = {"GBP": "£", "USD": "$", "EUR": "€"}


def _to_decimal(value: Numeric) -> Decimal:
    if isinstance(value, Decimal):
        return value
    # str() first so float inputs (e.g. 12.8) don't carry binary noise.
    return Decimal(str(value))


@dataclass(frozen=True)
class Money:
    amount: Decimal
    currency: str = "GBP"

    def __post_init__(self) -> None:
        object.__setattr__(self, "amount", _to_decimal(self.amount))
        object.__setattr__(self, "currency", self.currency.upper())

    @classmethod
    def of(cls, amount: Numeric, currency: str = "GBP") -> Money:
        return cls(_to_decimal(amount), currency)

    @classmethod
    def gbp(cls, amount: Numeric) -> Money:
        return cls(_to_decimal(amount), "GBP")

    @classmethod
    def zero(cls, currency: str = "GBP") -> Money:
        return cls(Decimal("0"), currency)

    def _assert_same(self, other: Money) -> None:
        if self.currency != other.currency:
            raise ValueError(
                f"Currency mismatch: {self.currency} vs {other.currency}. "
                "Use Money.convert() with an explicit FX rate first."
            )

    def __add__(self, other: Money) -> Money:
        self._assert_same(other)
        return Money(self.amount + other.amount, self.currency)

    def __sub__(self, other: Money) -> Money:
        self._assert_same(other)
        return Money(self.amount - other.amount, self.currency)

    def __mul__(self, factor: Numeric) -> Money:
        return Money(self.amount * _to_decimal(factor), self.currency)

    def __rmul__(self, factor: Numeric) -> Money:
        return self.__mul__(factor)

    def __lt__(self, other: Money) -> bool:
        self._assert_same(other)
        return self.amount < other.amount

    def __le__(self, other: Money) -> bool:
        self._assert_same(other)
        return self.amount <= other.amount

    def __gt__(self, other: Money) -> bool:
        self._assert_same(other)
        return self.amount > other.amount

    def __ge__(self, other: Money) -> bool:
        self._assert_same(other)
        return self.amount >= other.amount

    def quantize(self) -> Money:
        """Round to 2 decimal places (half-up) — the cash representation."""
        return Money(self.amount.quantize(TWO_PLACES, rounding=ROUND_HALF_UP), self.currency)

    def convert(self, rate: Numeric, to_currency: str) -> Money:
        """Apply an explicit FX rate, producing money in ``to_currency``."""
        return Money(self.amount * _to_decimal(rate), to_currency)

    @property
    def as_float(self) -> float:
        return float(self.amount)

    def __str__(self) -> str:
        symbol = _SYMBOLS.get(self.currency, f"{self.currency} ")
        return f"{symbol}{self.amount.quantize(TWO_PLACES, rounding=ROUND_HALF_UP)}"
