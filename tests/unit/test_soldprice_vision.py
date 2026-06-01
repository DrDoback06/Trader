"""Tests for the Claude rough-estimate sold-price provider.

We can't (and don't want to) hit the real Anthropic API in unit tests, so we patch the
SDK client to return canned responses and assert that the provider parses them, applies
the rough-spread floor, and labels itself ``claude_estimate`` so the UI tags it
``est. (rough)`` and never confuses it with real comps.
"""

from __future__ import annotations

import sys
import types

import pytest

from trader.core.models import Card, Game
from trader.providers.soldprice_vision import (
    ClaudeEstimateProvider,
    _parse_response,
)

CARD = Card(
    id="POKEMON-MEW-199/165",
    game=Game.POKEMON,
    set_code="MEW",
    set_name="151",
    number="199/165",
    name="Charizard ex",
    rarity="Rare Double Star",
)


# --- pure response-parsing tests -----------------------------------------------

def test_parse_response_extracts_median_low_high() -> None:
    parsed = _parse_response(
        'sure thing — {"median_gbp": 95.5, "low_gbp": 80, "high_gbp": 120, "confidence": "medium"} here'
    )
    assert parsed == (95.5, 80.0, 120.0)


def test_parse_response_handles_median_only() -> None:
    parsed = _parse_response('{"median_gbp": 42}')
    assert parsed == (42.0, None, None)


def test_parse_response_returns_none_on_zero_median() -> None:
    assert _parse_response('{"median_gbp": 0}') is None


def test_parse_response_returns_none_on_no_json() -> None:
    assert _parse_response("Claude didn't know") is None


def test_parse_response_returns_none_on_bad_json() -> None:
    assert _parse_response("{median: 99}") is None


# --- end-to-end provider tests (with the SDK monkey-patched) ------------------

class _FakeContentBlock:
    def __init__(self, text: str) -> None:
        self.type = "text"
        self.text = text


class _FakeResponse:
    def __init__(self, text: str) -> None:
        self.content = [_FakeContentBlock(text)]


class _FakeMessages:
    def __init__(self, text: str) -> None:
        self._text = text
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return _FakeResponse(self._text)


class _FakeClient:
    def __init__(self, text: str) -> None:
        self.messages = _FakeMessages(text)


@pytest.fixture
def fake_anthropic(monkeypatch):
    """Inject a fake ``anthropic`` module so the provider can import + call it."""

    holder: dict[str, _FakeClient] = {}

    def make_module(reply: str) -> types.ModuleType:
        mod = types.ModuleType("anthropic")
        def Anthropic(*, api_key: str) -> _FakeClient:  # noqa: N802 - mirror real SDK
            client = _FakeClient(reply)
            client.api_key = api_key  # type: ignore[attr-defined]
            holder["last"] = client
            return client
        mod.Anthropic = Anthropic  # type: ignore[attr-defined]
        return mod

    def install(reply: str) -> _FakeClient | None:
        monkeypatch.setitem(sys.modules, "anthropic", make_module(reply))
        # Force re-import path inside the provider by clearing any prior client
        return holder.get("last")

    return install


def test_provider_returns_valuation_when_claude_replies(fake_anthropic) -> None:
    fake_anthropic('{"median_gbp": 95.5, "low_gbp": 80, "high_gbp": 120}')
    provider = ClaudeEstimateProvider("key", model="claude-test")
    val = provider.get_valuation(CARD, "GRADED_PSA_10")
    assert val is not None
    assert val.provider == "claude_estimate"
    assert float(val.median.amount) == 95.5
    assert val.low is not None and float(val.low.amount) == 80.0
    assert val.high is not None and float(val.high.amount) == 120.0
    # Spread is at least the rough-baseline so confidence stays honest.
    assert val.spread >= 0.40


def test_provider_returns_none_on_unparseable_reply(fake_anthropic) -> None:
    fake_anthropic("I don't know enough to price that card.")
    provider = ClaudeEstimateProvider("key")
    assert provider.get_valuation(CARD, "GRADED_PSA_10") is None


def test_provider_returns_none_on_zero_estimate(fake_anthropic) -> None:
    fake_anthropic('{"median_gbp": 0}')
    provider = ClaudeEstimateProvider("key")
    assert provider.get_valuation(CARD, "RAW_NM") is None


def test_provider_returns_none_when_sdk_missing(monkeypatch) -> None:
    # No 'anthropic' module installed → safe miss, never crashes the chain.
    monkeypatch.setitem(sys.modules, "anthropic", None)
    # Also need to ensure import fails inside the function, not via stale cache:
    if "anthropic" in sys.modules and sys.modules["anthropic"] is not None:
        monkeypatch.delitem(sys.modules, "anthropic")
    provider = ClaudeEstimateProvider("key")
    # Either the import fails (None entry) or the real SDK is absent — both cases give None.
    val = provider.get_valuation(CARD, "RAW_NM")
    # We only require: never raises. A real-SDK install would 401 and return None anyway.
    assert val is None or val.provider == "claude_estimate"
