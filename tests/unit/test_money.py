from __future__ import annotations

from decimal import Decimal

import pytest

from trader.core.money import Money


def test_construction_and_float_inputs_are_exact() -> None:
    assert Money.gbp("12.80").amount == Decimal("12.80")
    # str() coercion avoids binary float noise
    assert Money.gbp(0.1).amount == Decimal("0.1")


def test_arithmetic() -> None:
    assert (Money.gbp(10) + Money.gbp(5)).amount == Decimal("15")
    assert (Money.gbp(10) - Money.gbp(4)).amount == Decimal("6")
    assert (Money.gbp(10) * Decimal("0.5")).amount == Decimal("5.0")
    assert (3 * Money.gbp(2)).amount == Decimal("6")


def test_quantize_half_up() -> None:
    assert Money.gbp("5.255").quantize().amount == Decimal("5.26")


def test_comparisons() -> None:
    assert Money.gbp(5) < Money.gbp(6)
    assert Money.gbp(6) >= Money.gbp(6)


def test_currency_mismatch_raises() -> None:
    with pytest.raises(ValueError, match="Currency mismatch"):
        _ = Money.gbp(1) + Money.of(1, "USD")


def test_convert_applies_explicit_rate() -> None:
    usd = Money.of(100, "USD")
    gbp = usd.convert("0.79", "GBP")
    assert gbp.currency == "GBP"
    assert gbp.amount == Decimal("79.00")


def test_str_formats_symbol() -> None:
    assert str(Money.gbp("12.8")) == "£12.80"
