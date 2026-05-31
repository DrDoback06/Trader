"""Extract eBay's *own* error message from a failed Browse/OAuth response.

The app used to swallow eBay's error and substitute a guess (e.g. "these are
sandbox keys"), which sent users chasing the wrong fix. eBay actually tells you
exactly what's wrong — surface it.

Two body shapes:
* Browse/REST errors: ``{"errors": [{"errorId": 1100, "message": ...,
  "longMessage": ...}]}`` — e.g. errorId 1100 ("Insufficient permissions to
  fulfill the request") means the keyset lacks Buy/Browse production access, so
  re-pasting keys can't help.
* OAuth token errors: ``{"error": "invalid_client", "error_description": ...}``.
"""

from __future__ import annotations

import httpx


def ebay_error_detail(exc: httpx.HTTPStatusError) -> str:
    """eBay's own error text (with errorId), or "" when the body isn't eBay JSON."""
    try:
        body = exc.response.json()
    except (ValueError, AttributeError):
        return ""
    if not isinstance(body, dict):
        return ""

    errors = body.get("errors")
    if isinstance(errors, list) and errors and isinstance(errors[0], dict):
        err = errors[0]
        msg = (err.get("longMessage") or err.get("message") or "").strip()
        eid = err.get("errorId")
        if msg and eid is not None:
            return f"{msg} (eBay errorId {eid})"
        return msg

    if body.get("error"):  # OAuth2 token-endpoint error shape
        desc = (body.get("error_description") or "").strip()
        return f"{body['error']}: {desc}".strip(": ").strip()

    return ""
