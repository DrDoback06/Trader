import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchDeals, runScan } from "../api";
import type { Deal } from "../types";
import { DealsTable } from "./DealsTable";

export function DealsPage() {
  const [deals, setDeals] = useState<Deal[]>([]);
  const [onlyPassing, setOnlyPassing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanMsg, setScanMsg] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    fetchDeals(onlyPassing)
      .then((d) => {
        setDeals(d);
        setError(null);
      })
      .catch((err: unknown) => setError(err instanceof Error ? err.message : "failed to load"))
      .finally(() => setLoading(false));
  }, [onlyPassing]);

  useEffect(() => load(), [load]);

  const onScan = async () => {
    setScanning(true);
    setScanMsg(null);
    try {
      const r = await runScan();
      setScanMsg(
        `Scanned ${r.targets_scanned} targets · ${r.listings_seen} listings · ${r.new_listings} new.`,
      );
      load();
    } catch (err: unknown) {
      setScanMsg(err instanceof Error ? err.message : "scan failed");
    } finally {
      setScanning(false);
    }
  };

  const stats = useMemo(() => {
    const passing = deals.filter((d) => d.passed_rules);
    const green = passing.filter((d) => d.profit_tier === "GREEN").length;
    const potential = passing.reduce(
      (sum, d) => sum + (d.economics ? d.economics.profit.amount : 0),
      0,
    );
    return { evaluated: deals.length, passing: passing.length, green, potential };
  }, [deals]);

  return (
    <>
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
          <span className="figure green-fig">{stats.green}</span>
          <span className="label">green-light (high profit)</span>
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
        <button className="primary" onClick={onScan} disabled={scanning}>
          {scanning ? "Scanning…" : "↻ Run live eBay scan"}
        </button>
        {scanMsg && <span className="scanmsg">{scanMsg}</span>}
      </div>

      {loading && <p className="empty">Loading…</p>}
      {error && (
        <p className="error">
          {error}. Is the backend running on <code>http://localhost:8000</code>?
        </p>
      )}
      {!loading && !error && <DealsTable deals={deals} />}
    </>
  );
}
