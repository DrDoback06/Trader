import { useEffect, useState } from "react";
import { fetchGems } from "../api";
import type { GemCard } from "../types";

export function HiddenGemsPage({ onPick }: { onPick: (query: string) => void }) {
  const [gems, setGems] = useState<GemCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [minValue, setMinValue] = useState<string>("");
  const [limit, setLimit] = useState(60);

  useEffect(() => {
    setLoading(true);
    const min = Number(minValue);
    fetchGems({
      limit,
      min_value: Number.isFinite(min) && min > 0 ? min : undefined,
    })
      .then((r) => {
        setGems(r.gems);
        setError(null);
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "load failed"))
      .finally(() => setLoading(false));
  }, [minValue, limit]);

  return (
    <div className="gems">
      <h2>💎 Hidden Gems</h2>
      <p className="sub">
        Cards ranked by <strong>value vs. attention</strong> — high estimated value, few competing
        listings, low watcher count. The opposite of the standard Deals ranking, which prefers
        liquid grails. Scores populate after each live scan: as the app values more of your card
        list, the gem ranking sharpens.
      </p>
      <div className="controls filterbar">
        <label className="field">
          Min market value (£)
          <input
            type="number"
            min="0"
            value={minValue}
            onChange={(e) => setMinValue(e.target.value)}
            placeholder="0"
            style={{ width: 80 }}
          />
        </label>
        <label className="field">
          Show
          <select value={limit} onChange={(e) => setLimit(Number(e.target.value))}>
            <option value="30">Top 30</option>
            <option value="60">Top 60</option>
            <option value="120">Top 120</option>
          </select>
        </label>
        <span className="spacer" />
        <span className="count">{gems.length} card(s)</span>
      </div>

      {loading && <p className="empty">Loading…</p>}
      {error && <p className="error">{error}</p>}

      {!loading && !error && gems.length === 0 && (
        <p className="empty">
          No gems yet — run a live scan on your card list (Deals → ↻ Scan), or hit{" "}
          <strong>🔎 Search live listings</strong> on a card to value it. Gems appear once the
          insights cache has values for cards with low listing saturation.
        </p>
      )}

      {!loading && !error && gems.length > 0 && (
        <div className="cardgrid">
          {gems.map((g) => {
            const query = `${g.card.name} ${g.card.number}`;
            return (
              <div key={g.card.id} className="cardtile gem">
                <div className="badgerow">
                  <span className="badge-gem" title={`Gem score ${g.gem_score.toFixed(1)}`}>
                    💎 {g.gem_score.toFixed(0)}
                  </span>
                  {g.median && <span className="badge-value">{g.median.display}</span>}
                  {g.active_listings_count != null && (
                    <span className="badge-active" title="Active eBay listings">
                      🏷️ {g.active_listings_count}
                    </span>
                  )}
                </div>
                <button className="cardtap" onClick={() => onPick(query)} title="Search live listings">
                  {g.image_url ? (
                    <img src={g.image_url} alt="" loading="lazy" />
                  ) : (
                    <div className="noimg">{g.card.number}</div>
                  )}
                  <div className="cardname">{g.card.name}</div>
                  <div className="sub">
                    {g.card.set_name} · {g.card.number}
                    {g.card.rarity ? ` · ${g.card.rarity}` : ""}
                  </div>
                </button>
                {g.cheapest_listing && (
                  <div className="sub" title="Cheapest active listing seen for this card">
                    cheapest: {g.cheapest_listing.display}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
