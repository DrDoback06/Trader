from __future__ import annotations

import base64
import warnings

from fastapi.testclient import TestClient

from trader.main import app

warnings.filterwarnings("ignore")


def _basic(password: str) -> dict[str, str]:
    token = base64.b64encode(f"user:{password}".encode()).decode()
    return {"Authorization": f"Basic {token}"}


def test_open_when_no_password() -> None:
    app.state.settings.access_password = ""
    client = TestClient(app)
    assert client.get("/health").status_code == 200
    assert client.get("/deals").status_code == 200


def test_password_gates_everything_except_health() -> None:
    app.state.settings.access_password = "s3cret"
    try:
        client = TestClient(app)
        assert client.get("/health").status_code == 200  # health stays open for Render
        assert client.get("/deals").status_code == 401  # gated without creds
        assert client.get("/deals", headers=_basic("nope")).status_code == 401
        assert client.get("/deals", headers=_basic("s3cret")).status_code == 200
    finally:
        app.state.settings.access_password = ""  # reset for other tests sharing `app`
