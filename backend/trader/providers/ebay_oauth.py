"""eBay OAuth2 client-credentials token minting, with caching.

Token mint is itself rate-limited, so we cache the app token until ~5 minutes
before expiry.
"""

from __future__ import annotations

import base64
import time

import httpx

_SAFETY_WINDOW_S = 300.0
DEFAULT_SCOPE = "https://api.ebay.com/oauth/api_scope"


class EbayOAuth:
    def __init__(
        self,
        client_id: str,
        client_secret: str,
        token_url: str,
        *,
        scope: str = DEFAULT_SCOPE,
        client: httpx.Client | None = None,
    ) -> None:
        self._id = client_id
        self._secret = client_secret
        self._url = token_url
        self._scope = scope
        self._client = client or httpx.Client(timeout=20.0)
        self._token: str | None = None
        self._expires_at = 0.0

    def _basic_auth(self) -> str:
        return base64.b64encode(f"{self._id}:{self._secret}".encode()).decode()

    def token(self) -> str:
        now = time.time()
        if self._token is not None and now < self._expires_at - _SAFETY_WINDOW_S:
            return self._token
        resp = self._client.post(
            self._url,
            headers={
                "Authorization": f"Basic {self._basic_auth()}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"grant_type": "client_credentials", "scope": self._scope},
        )
        resp.raise_for_status()
        body = resp.json()
        self._token = str(body["access_token"])
        self._expires_at = now + float(body.get("expires_in", 7200))
        return self._token
