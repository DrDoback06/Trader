import { useCallback, useEffect, useMemo, useState } from "react";
import { buyDeal, evaluateCard, fetchDeals, runScan } from "../api";
import type { Deal } from "../types";
import { DealsTable } from "./DealsTable";

export function DealsPage() {
  const [deals, setDeals] = useState<Deal[]>([]);
  const [onlyPassing, setOnlyPassing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanMsg, setScanMsg] = useState<string | null>(null);
  const [mode, setMode] = useState("everything");
  const [hours, setHours] = useState(6);
  const [scanned, setScanned] = useState(false);
  const [hideSamples, setHideSamples] = useState(false);

  // "Check a card" — a real valuation using your live sold-price key, no eBay key needed.
  const [checks, setChecks] = useState<Deal[]>([]);
  const [cardQuery, setCardQuery] = useState("");
  const [askPrice, setAskPrice] = useState("");
  const [postage, setPostage] = useState("");
  const [checking, setChecking] = useState(false);
  const [checkMsg, setCheckMsg] = useState<string | null>(null);

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
      const r = await runScan({ mode, ending_within_hours: hours });
      setScanMsg(
        `Scoured ${r.listings_seen} listings · ${r.new_listings} new${
          r.quota_exhausted ? " (daily call budget hit)" : ""
        }.`,
      );
      setScanned(true);
      load();
    } catch (err: unknown) {
      setScanMsg(err instanceof Error ? err.message : "scan failed");
    } finally {
      setScanning(false);
    }
  };

  const onCheck = async () => {
    const price = Number(askPrice);
    if (cardQuery.trim().length < 3 || !Number.isFinite(price) || price <= 0) {
      setCheckMsg("Enter a card name and the price you'd pay.");
      return;
    }
    setChecking(true);
    setCheckMsg(null);
    try {
      const ship = Number(postage);
      const result = await evaluateCard({
        query: cardQuery.trim(),
        ask_price: price,
        shipping: Number.isFinite(ship) && ship > 0 ? ship : undefined,
      });
      setChecks((prev) => [result, ...prev.filter((d) => d.id !== result.id)]);
      setCheckMsg(
        result.valuation
          ? null
          : "No UK sold-price data found for that search. Try the exact card name + number, the way you'd type it on eBay.",
      );
    } catch (err: unknown) {
      setCheckMsg(err instanceof Error ? err.message : "check failed");
    } finally {
      setChecking(false);
    }
  };

  const onBuy = async (dealId: string) => {
    try {
      await buyDeal(dealId);
      setScanMsg("Added to your portfolio 📌");
    } catch (err: unknown) {
      setScanMsg(err instanceof Error ? err.message : "could not add to portfolio");
    }
  };

  const showHours = mode === "ending_soon" || mode === "everything";
  const showSamples = !scanned && !hideSamples;

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

      <div className="checkcard">
        <h2>Check a card</h2>
        <p className="sub">
          A real valuation using your live eBay-UK sold-price key — no eBay listing key needed.
          Type a card the way you'd search eBay, plus the price you'd pay.
        </p>
        <div className="controls">
          <label className="field grow">
            Card
            <input
              type="text"
              placeholder="e.g. Charizard ex 199/165   ·   Pikachu 173/165 PSA 10"
              value={cardQuery}
              onChange={(e) => setCardQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") onCheck();
              }}
            />
          </label>
          <label className="field">
            You'd pay £
            <input
              type="number"
              min="0"
              step="0.01"
              value={askPrice}
              onChange={(e) => setAskPrice(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") onCheck();
              }}
            />
          </label>
          <label className="field">
            + postage £
            <input
              type="number"
              min="0"
              step="0.01"
              value={postage}
              onChange={(e) => setPostage(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") onCheck();
              }}
            />
          </label>
          <button className="primary" onClick={onCheck} disabled={checking}>
            {checking ? "Checking…" : "Check value"}
          </button>
          {checkMsg && <span className="scanmsg">{checkMsg}</span>}
        </div>
        {checks.length > 0 && (
          <>
            <DealsTable deals={checks} onBuy={onBuy} />
            <button className="linkbtn" onClick={() => setChecks([])}>
              Clear checks
            </button>
          </>
        )}
      </div>

      <div className="controls">
        <label className="toggle">
          <input
            type="checkbox"
            checked={onlyPassing}
            onChange={(e) => setOnlyPassing(e.target.checked)}
          />
          Only deals that clear my buy rules
        </label>

        <span className="spacer" />

        <label className="field">
          Scan
          <select value={mode} onChange={(e) => setMode(e.target.value)}>
            <option value="everything">Everything (scour eBay)</option>
            <option value="cheapest">Cheapest BIN &amp; offers</option>
            <option value="ending_soon">Auctions ending soon</option>
            <option value="hidden_gems">Hidden gems (typos)</option>
            <option value="graded">Graded slabs (PSA/CGC)</option>
            <option value="sealed">Sealed boxes / ETBs</option>
            <option value="watchlist">My watchlist cards</option>
          </select>
        </label>

        {showHours && (
          <label className="field">
            ending within
            <select value={hours} onChange={(e) => setHours(Number(e.target.value))}>
              {[1, 2, 3, 6, 12].map((h) => (
                <option key={h} value={h}>
                  {h}h
                </option>
              ))}
            </select>
          </label>
        )}

        <button className="primary" onClick={onScan} disabled={scanning}>
          {scanning ? "Scanning…" : "↻ Run live eBay scan"}
        </button>
        {scanMsg && <span className="scanmsg">{scanMsg}</span>}
      </div>

      {showSamples && (
        <div className="note">
          ⚠️ The table below is <strong>sample data</strong> to show the layout — not live
          listings. Add your eBay keys and run a scan for real deals, or use{" "}
          <strong>Check a card</strong> above right now.{" "}
          <button className="linkbtn" onClick={() => setHideSamples(true)}>
            Hide samples
          </button>
        </div>
      )}

      {loading && <p className="empty">Loading…</p>}
      {error && (
        <p className="error">
          {error}. Is the backend running on <code>http://localhost:8000</code>?
        </p>
      )}
      {!loading && !error && !hideSamples && <DealsTable deals={deals} onBuy={onBuy} />}
      {!loading && !error && hideSamples && !scanned && (
        <p className="empty">
          Samples hidden. Use “Check a card” above, or run a live scan once your eBay keys are in.
        </p>
      )}
    </>
  );
}
