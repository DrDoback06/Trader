"""Import the full Pokémon card catalogue from pokemontcg.io.

Run this LOCALLY (the API isn't reachable from every sandbox):

    python -m trader.tools.import_pokemontcg
    # optional, for higher rate limits:
    POKEMONTCG_API_KEY=xxxx python -m trader.tools.import_pokemontcg

It writes one JSON file per set into backend/trader/catalogue_data/imported/
(gitignored). The app automatically prefers that folder over the seed sets, so a
"scour" scan can then recognise tens of thousands of cards across every set.

The transform functions are pure and unit-tested; only `fetch_all_cards`/`main`
touch the network.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from pathlib import Path
from typing import Any

import httpx

API_URL = "https://api.pokemontcg.io/v2/cards"
_DEFAULT_OUT = Path(__file__).resolve().parent.parent / "catalogue_data" / "imported"


# --- pure transforms (no network) ---------------------------------------------

def set_code(set_obj: dict[str, Any]) -> str:
    code = str(set_obj.get("ptcgoCode") or "").strip()
    return code.upper() if code else str(set_obj.get("id", "")).upper()


def card_number(card: dict[str, Any], set_obj: dict[str, Any]) -> str:
    """eBay-style number: '199/165' for numbered cards, raw for promos (SWSH001…)."""
    num = str(card.get("number", "")).strip()
    printed = set_obj.get("printedTotal") or set_obj.get("total")
    if num.isdigit() and printed:
        return f"{int(num)}/{int(printed)}"
    return num


def to_catalogue_card(card: dict[str, Any]) -> dict[str, Any]:
    set_obj = card.get("set") or {}
    out: dict[str, Any] = {"number": card_number(card, set_obj), "name": card.get("name", "")}
    if card.get("rarity"):
        out["rarity"] = card["rarity"]
    image = (card.get("images") or {}).get("small", "")
    if image:
        out["image"] = image
    return out


def group_to_sets(cards: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    sets: dict[str, dict[str, Any]] = {}
    for card in cards:
        set_obj = card.get("set") or {}
        code = set_code(set_obj)
        if not code or not card.get("name") or not card.get("number"):
            continue
        entry = sets.setdefault(
            code,
            {
                "game": "POKEMON",
                "set_code": code,
                "set_name": set_obj.get("name", code),
                "set_image": (set_obj.get("images") or {}).get("logo", ""),
                "cards": [],
            },
        )
        entry["cards"].append(to_catalogue_card(card))
    return sets


def write_sets(sets: dict[str, dict[str, Any]], out_dir: str | Path) -> int:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for code, payload in sets.items():
        safe = re.sub(r"[^A-Za-z0-9_-]", "_", code) or "UNKNOWN"
        (out / f"{safe}.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8"
        )
    return len(sets)


# --- network runner ------------------------------------------------------------

def _get_with_retry(
    client: httpx.Client, params: dict[str, Any], headers: dict[str, str], tries: int = 8
) -> httpx.Response:
    delay = 2.0
    for attempt in range(tries):
        try:
            resp = client.get(API_URL, params=params, headers=headers)
        except httpx.HTTPError as exc:  # timeouts, connection resets, DNS, etc.
            if attempt == tries - 1:
                raise
            print(f"    network error ({type(exc).__name__}); retrying in {delay:.0f}s…")
            time.sleep(delay)
            delay = min(delay * 2, 30.0)
            continue
        if resp.status_code == 429 or resp.status_code >= 500:
            if attempt == tries - 1:
                resp.raise_for_status()
            wait = float(resp.headers.get("Retry-After") or delay)
            print(f"    rate-limited/{resp.status_code}; retrying in {wait:.0f}s…")
            time.sleep(wait)
            delay = min(delay * 2, 30.0)
            continue
        resp.raise_for_status()
        return resp
    raise RuntimeError("unreachable")


def fetch_all_cards(
    *,
    api_key: str | None = None,
    page_size: int = 250,
    sleep: float = 0.25,
    client: httpx.Client | None = None,
    checkpoint_dir: str | Path | None = None,
) -> list[dict[str, Any]]:
    client = client or httpx.Client(timeout=httpx.Timeout(90.0, connect=30.0))
    headers = {"X-Api-Key": api_key} if api_key else {}

    cards_path: Path | None = None
    state_path: Path | None = None
    if checkpoint_dir is not None:
        cp = Path(checkpoint_dir)
        cp.mkdir(parents=True, exist_ok=True)
        cards_path = cp / "_import_cards.jsonl"
        state_path = cp / "_import_state.json"

    cards: list[dict[str, Any]] = []
    page = 1
    # Resume a previously-interrupted import if a checkpoint is present.
    if cards_path and state_path and cards_path.exists() and state_path.exists():
        cards = [
            json.loads(line)
            for line in cards_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        page = int(json.loads(state_path.read_text(encoding="utf-8")).get("next_page", 1))
        print(f"  resuming from page {page} ({len(cards)} cards already saved)")

    while True:
        resp = _get_with_retry(
            client,
            {"page": page, "pageSize": page_size, "select": "id,name,number,rarity,set,images"},
            headers,
        )
        data = resp.json()
        batch = data.get("data") or []
        cards.extend(batch)
        total = int(data.get("totalCount", 0))
        print(f"  page {page}: +{len(batch)} ({len(cards)}/{total})")
        if cards_path and state_path:  # checkpoint after each page so drops don't lose work
            with cards_path.open("a", encoding="utf-8") as f:
                for c in batch:
                    f.write(json.dumps(c, ensure_ascii=False) + "\n")
            state_path.write_text(json.dumps({"next_page": page + 1}), encoding="utf-8")
        if not batch or len(cards) >= total:
            break
        page += 1
        time.sleep(sleep)
    return cards


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Import the full Pokémon catalogue.")
    parser.add_argument("--out", default=str(_DEFAULT_OUT))
    parser.add_argument("--api-key", default=os.environ.get("POKEMONTCG_API_KEY"))
    parser.add_argument("--page-size", type=int, default=250)
    args = parser.parse_args(argv)

    print("Fetching every Pokémon card from pokemontcg.io … (a few minutes)")
    print("If your connection drops, just run this again — it resumes where it left off.")
    cards = fetch_all_cards(
        api_key=args.api_key, page_size=args.page_size, checkpoint_dir=args.out
    )
    sets = group_to_sets(cards)
    total_cards = sum(len(s["cards"]) for s in sets.values())
    n = write_sets(sets, args.out)
    # Import finished cleanly — clear the resume checkpoint.
    for name in ("_import_cards.jsonl", "_import_state.json"):
        (Path(args.out) / name).unlink(missing_ok=True)
    print(f"\nDone: {total_cards} cards across {n} sets -> {args.out}")
    print("Restart the backend; the app will now use the full catalogue.")


if __name__ == "__main__":
    main()
