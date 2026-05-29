import { useEffect, useMemo, useState } from "react";
import { fetchSetCards, fetchSets } from "../api";
import type { CatalogueCard, SetInfo } from "../types";

export function BrowsePage({ onPick }: { onPick: (query: string) => void }) {
  const [sets, setSets] = useState<SetInfo[]>([]);
  const [total, setTotal] = useState(0);
  const [active, setActive] = useState<SetInfo | null>(null);
  const [cards, setCards] = useState<CatalogueCard[]>([]);
  const [loadingCards, setLoadingCards] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [setFilter, setSetFilter] = useState("");
  const [cardFilter, setCardFilter] = useState("");

  useEffect(() => {
    fetchSets()
      .then((r) => {
        setSets(r.sets);
        setTotal(r.total_cards);
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load sets"));
  }, []);

  const openSet = (s: SetInfo) => {
    setActive(s);
    setCards([]);
    setCardFilter("");
    setLoadingCards(true);
    fetchSetCards(s.set_code)
      .then((r) => setCards(r.cards))
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load cards"))
      .finally(() => setLoadingCards(false));
  };

  const visibleSets = useMemo(
    () => sets.filter((s) => s.set_name.toLowerCase().includes(setFilter.toLowerCase())),
    [sets, setFilter],
  );
  const visibleCards = useMemo(
    () =>
      cards.filter((c) =>
        `${c.name} ${c.number}`.toLowerCase().includes(cardFilter.toLowerCase()),
      ),
    [cards, cardFilter],
  );

  if (error) {
    return <p className="error">{error}</p>;
  }

  if (!active) {
    return (
      <div className="browse">
        <h2>Browse the catalogue</h2>
        <p className="sub">
          {total.toLocaleString()} cards across {sets.length} sets. Tap a set, then tap a card to
          value it instantly.{" "}
          {total < 100 &&
            "Only the bundled sample sets are loaded — run ./run.bat --catalogue (or import_pokemontcg) once for every set + card images."}
        </p>
        <div className="controls">
          <label className="field grow">
            Find a set
            <input
              type="text"
              value={setFilter}
              placeholder="e.g. 151, Obsidian, Base"
              onChange={(e) => setSetFilter(e.target.value)}
            />
          </label>
        </div>
        <div className="settiles">
          {visibleSets.map((s) => (
            <button key={s.set_code} className="settile" onClick={() => openSet(s)}>
              {s.image ? (
                <img src={s.image} alt="" loading="lazy" />
              ) : (
                <div className="setcode">{s.set_code}</div>
              )}
              <div className="setname">{s.set_name}</div>
              <div className="sub">{s.count} cards</div>
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="browse">
      <div className="controls">
        <button className="linkbtn" onClick={() => setActive(null)}>
          ← All sets
        </button>
        <span className="spacer" />
        <label className="field grow">
          Find a card
          <input
            type="text"
            value={cardFilter}
            placeholder="name or number"
            onChange={(e) => setCardFilter(e.target.value)}
          />
        </label>
      </div>
      <h2>{active.set_name}</h2>
      <p className="sub">
        {visibleCards.length} of {cards.length} cards · tap a card to value it
      </p>
      {loadingCards ? (
        <p className="empty">Loading…</p>
      ) : (
        <div className="cardgrid">
          {visibleCards.map((c) => (
            <button
              key={c.id}
              className="cardtile"
              title="Value this card"
              onClick={() => onPick(`${c.name} ${c.number}`)}
            >
              {c.image_url ? (
                <img src={c.image_url} alt="" loading="lazy" />
              ) : (
                <div className="noimg">{c.number}</div>
              )}
              <div className="cardname">{c.name}</div>
              <div className="sub">
                {c.number}
                {c.rarity ? ` · ${c.rarity}` : ""}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
