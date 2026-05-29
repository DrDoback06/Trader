from __future__ import annotations

import pytest

from trader.providers.soldprice_rapidapi import velocity_from_products


def test_velocity_needs_two_dates() -> None:
    assert velocity_from_products([{"date_sold": "2024-01-01"}]) == (None, None)
    assert velocity_from_products([]) == (None, None)


def test_velocity_computes_rate_and_days() -> None:
    # 4 sales spread weekly over 21 days ≈ 1.33/week.
    products = [{"date_sold": f"2024-01-{day:02d}"} for day in (1, 8, 15, 22)]
    sales_per_week, days_to_sell = velocity_from_products(products)
    assert sales_per_week is not None and days_to_sell is not None
    assert 1.0 <= sales_per_week <= 1.7
    assert days_to_sell == pytest.approx(7.0 / sales_per_week, abs=0.1)


def test_velocity_handles_unparseable_dates() -> None:
    assert velocity_from_products([{"date_sold": "??"}, {"date_sold": "n/a"}]) == (None, None)
