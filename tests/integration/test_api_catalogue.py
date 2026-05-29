from __future__ import annotations

import warnings

from fastapi.testclient import TestClient

from trader.main import app

warnings.filterwarnings("ignore")


def test_catalogue_lists_sets_and_cards() -> None:
    app.state.settings.access_password = ""
    client = TestClient(app)
    sets = client.get("/catalogue/sets").json()
    assert sets["total_cards"] >= 1
    assert len(sets["sets"]) >= 1
    # Each set carries a code, name, count and (possibly empty) image.
    first_set = sets["sets"][0]
    assert {"set_code", "set_name", "count", "image"} <= first_set.keys()

    code = first_set["set_code"]
    cards = client.get(f"/catalogue/sets/{code}/cards").json()
    assert len(cards["cards"]) >= 1
    card = cards["cards"][0]
    assert {"name", "number", "image_url"} <= card.keys()


def test_catalogue_unknown_set_is_404() -> None:
    client = TestClient(app)
    assert client.get("/catalogue/sets/NOPE/cards").status_code == 404
