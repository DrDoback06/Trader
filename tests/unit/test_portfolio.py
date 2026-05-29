from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from trader.core.models import Deal
from trader.db.base import init_db, make_engine, session_factory
from trader.services.portfolio import buy_from_deal, mark_sold, portfolio_summary


def _session_maker(tmp_path: Path):  # type: ignore[no-untyped-def]
    engine = make_engine(f"sqlite:///{tmp_path}/portfolio.db")
    init_db(engine)
    return session_factory(engine)


def test_buy_then_pnl(tmp_path: Path, make_deal: Callable[..., Deal]) -> None:
    sm = _session_maker(tmp_path)
    deal = make_deal(profit=15, roi=0.5, margin=0.3, confidence=0.8, buy_cost=30, est_value=45)

    pid = buy_from_deal(sm, deal)
    summary = portfolio_summary(sm)
    assert summary["held"] == 1
    assert summary["invested"] == 30.0
    assert summary["unrealised_pnl"] == 15.0  # 45 market - 30 cost

    assert mark_sold(sm, pid, 50.0) is True
    after = portfolio_summary(sm)
    assert after["held"] == 0
    assert after["realised_pnl"] == 20.0  # 50 sold - 30 cost


def test_mark_sold_missing_position(tmp_path: Path) -> None:
    sm = _session_maker(tmp_path)
    assert mark_sold(sm, 999, 10.0) is False
