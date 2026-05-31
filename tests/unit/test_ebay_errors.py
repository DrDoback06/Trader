from __future__ import annotations

import httpx

from trader.providers.ebay_errors import ebay_error_detail


def _status_error(
    status: int, *, json: object | None = None, text: str = ""
) -> httpx.HTTPStatusError:
    request = httpx.Request("GET", "https://api.ebay.com/buy/browse/v1/item_summary/search")
    response = (
        httpx.Response(status, json=json, request=request)
        if json is not None
        else httpx.Response(status, text=text, request=request)
    )
    return httpx.HTTPStatusError("boom", request=request, response=response)


def test_browse_error_prefers_long_message_and_keeps_error_id() -> None:
    exc = _status_error(
        403,
        json={
            "errors": [
                {
                    "errorId": 1100,
                    "domain": "ACCESS",
                    "message": "Insufficient permissions to fulfill the request.",
                    "longMessage": "The application lacks Buy API access for this resource.",
                }
            ]
        },
    )
    detail = ebay_error_detail(exc)
    assert "The application lacks Buy API access" in detail  # longMessage preferred
    assert "errorId 1100" in detail


def test_browse_error_falls_back_to_message() -> None:
    exc = _status_error(
        403, json={"errors": [{"errorId": 1100, "message": "Insufficient permissions."}]}
    )
    assert ebay_error_detail(exc) == "Insufficient permissions. (eBay errorId 1100)"


def test_oauth_token_error_shape() -> None:
    exc = _status_error(
        400, json={"error": "invalid_client", "error_description": "client authentication failed"}
    )
    assert ebay_error_detail(exc) == "invalid_client: client authentication failed"


def test_non_json_body_returns_empty() -> None:
    assert ebay_error_detail(_status_error(500, text="<html>Gateway error</html>")) == ""


def test_empty_errors_list_returns_empty() -> None:
    assert ebay_error_detail(_status_error(403, json={"errors": []})) == ""
