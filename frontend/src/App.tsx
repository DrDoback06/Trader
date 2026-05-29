import { useEffect, useMemo, useState } from "react";
import { fetchDeals } from "./api";
import { DealsTable } from "./components/DealsTable";
import type { Deal } from "./types";

export default function App() {
  const [deals, setDeals] = useState<Deal[]>([]);
  const [onlyPassing, setOnlyPassing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    fetchDeals(onlyPassing)
      .then((d) => {
        if (active) {
          setDeals(d);
          setError(null);
        }
      })
      .catch((err: unknown) => {
        if (active) {
          setError(err instanceof Error ? err.message : "failed to load deals");
        }
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [onlyPassing]);

  const stats = useMemo(() => {
    const passing = deals.filter((d) => d.passed_rules);
    const potential = passing.reduce(
      (sum, d) => sum + (d.economics ? d.economics.profit.amount : 0),
      0,
    );
    return { evaluated: deals.length, passing: passing.length, potential };
  }, [deals]);

  return (
    <div className="app">
      <header className="topbar">
        <div>
          <h1>Trader</h1>
          <p className="tagline">UK TCG deal finder — find underpriced cards, buy manually, flip for profit.</p>
        </div>
        <span className="demo-pill">DEMO DATA · Phase 1</span>
      </header>

      <section className="stats">
        <div className="stat">
          <span className="figure">{stats.evaluated}</span>
          <span className="label">listings evaluated</span>
        </div>
        <div className="stat">
          <span className="figure">{stats.passing}</span>
          <span className="label">deals worth buying</span>
        </div>
        <div className="stat">
          <span className="figure pos">£{stats.potential.toFixed(2)}</span>
          <span className="label">potential profit (passing)</span>
        </div>
      </section>

      <div className="controls">
        <label className="toggle">
          <input
            type="checkbox"
            checked={onlyPassing}
            onChange={(e) => setOnlyPassing(e.target.checked)}
          />
          Show only deals that clear my buy rules
        </label>
      </div>

      {loading && <p className="empty">Loading…</p>}
      {error && (
        <p className="error">
          {error}. Is the backend running on <code>http://localhost:8000</code>?
        </p>
      )}
      {!loading && !error && <DealsTable deals={deals} />}

      <footer className="foot">
        Decision-support only — no automated buying. You are responsible for your own purchases and
        any UK tax obligations. Estimated values and fees are configurable approximations.
      </footer>
    </div>
  );
}
