from __future__ import annotations

from decimal import Decimal

import pytest

from trader.core.economics import FeeProfile, compute_economics, max_bid_for_target
from trader.core.money import Money


def test_golden_numbers_default_uk_profile() -> None:
    """Buy a £20 card (+£1 inbound), expected sale £40, default UK fees."""
    econ = compute_economics(
        ask_price=Money.gbp(20),
        est_value=Money.gbp(40),
        fee_profile=FeeProfile.default_uk(),
        inbound_postage=Money.gbp(1),
    )
    assert econ.buy_cost == Money.gbp("21.00")
    # 40 * (0.128 + 0.0035) = 5.26, + 0.30 fixed = 5.56
    assert econ.selling_fees == Money.gbp("5.56")
    # 40 - 5.56 - 1.55 outbound - 0.40 packaging = 32.49
    assert econ.net_proceeds == Money.gbp("32.49")
    assert econ.profit == Money.gbp("11.49")
    assert econ.roi == pytest.approx(11.49 / 21.0, abs=1e-4)
    assert econ.margin == pytest.approx(11.49 / 40.0, abs=1e-4)


def test_fees_can_eat_the_margin() -> None:
    econ = compute_economics(
        ask_price=Money.gbp(38),
        est_value=Money.gbp(40),
        fee_profile=FeeProfile.default_uk(),
    )
    assert econ.profit.amount < 0


def test_zero_buy_cost_does_not_divide_by_zero() -> None:
    econ = compute_economics(
        ask_price=Money.gbp(0),
        est_value=Money.gbp(10),
        fee_profile=FeeProfile.default_uk(),
    )
    assert econ.roi == 0.0


def test_currency_mismatch_between_ask_and_value_raises() -> None:
    with pytest.raises(ValueError, match="convert the valuation first"):
        compute_economics(
            ask_price=Money.gbp(10),
            est_value=Money.of(10, "USD"),
            fee_profile=FeeProfile.default_uk(),
        )


def test_acquisition_price_overrides_ask() -> None:
    fp = FeeProfile.default_uk()
    at_ask = compute_economics(ask_price=Money.gbp(50), est_value=Money.gbp(80), fee_profile=fp)
    via_offer = compute_economics(
        ask_price=Money.gbp(50),
        est_value=Money.gbp(80),
        fee_profile=fp,
        acquisition_price=Money.gbp(30),
    )
    assert via_offer.buy_cost == Money.gbp("30.00")
    assert via_offer.profit > at_ask.profit


def test_max_bid_clears_targets_and_one_pound_more_breaks_them() -> None:
    fp = FeeProfile.default_uk()
    mb = max_bid_for_target(
        est_value=Money.gbp(80), fee_profile=fp, min_roi=0.30, min_profit=Money.gbp(5)
    )
    at_max = compute_economics(ask_price=mb, est_value=Money.gbp(80), fee_profile=fp)
    assert at_max.roi >= 0.30 - 1e-6
    assert at_max.profit.amount >= Decimal("5") - Decimal("0.01")

    worse = compute_economics(
        ask_price=Money.gbp(float(mb.amount) + 1), est_value=Money.gbp(80), fee_profile=fp
    )
    assert worse.roi < 0.30 or worse.profit < Money.gbp(5)


def test_fees_are_config_driven_not_hardcoded() -> None:
    """A zero-fee private-seller profile yields profit = value - buy_cost."""
    free = FeeProfile(
        name="private",
        final_value_fee_pct=Decimal("0"),
        regulatory_operating_fee_pct=Decimal("0"),
        fixed_per_order=Money.zero(),
        default_packaging=Money.zero(),
        default_outbound_postage=Money.zero(),
    )
    econ = compute_economics(
        ask_price=Money.gbp(10), est_value=Money.gbp(25), fee_profile=free
    )
    assert econ.selling_fees == Money.zero()
    assert econ.profit == Money.gbp("15.00")
