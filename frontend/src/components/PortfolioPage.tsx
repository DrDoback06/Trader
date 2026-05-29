import { useEffect, useState } from "react";
import { buyDeal, fetchAllocation, fetchPortfolio, sellPosition } from "../api";
import type { Allocation, Portfolio } from "../types";
import { DealsTable } from "./DealsTable";

export function PortfolioPage() {
  const [budget, setBudget] = useState(300);
  const [alloc, setAlloc] = useState<Allocation | null>(null);
  const [pf, setPf] = useState<Portfolio | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const loadPf = () =>
    fetchPortfolio()
      .then(setPf)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load"));
  const loadAlloc = (b: number) =>
    fetchAllocation(b)
      .then(setAlloc)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load"));

  useEffect(() => {
    loadAlloc(budget);
    loadPf();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const onBuy = async (id: string) => {
    try {
      await buyDeal(id);
      setMsg("Added to holdings 📌");
      loadPf();
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "could not add");
    }
  };

  const onSell = async (id: number) => {
    const entered = window.prompt("Sold for £?");
    if (!entered) {
      return;
    }
    const price = Number(entered);
    if (Number.isNaN(price)) {
      return;
    }
    try {
      setPf(await sellPosition(id, price));
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "could not record sale");
    }
  };

  if (error) {
    return <p className="error">{error}</p>;
  }

  return (
    <div className="portfolio">
      <h2>Best buys for your budget</h2>
      <p className="sub">The basket that maximises expected profit within your capital.</p>
      <div className="controls">
        <label className="field">
          £
          <input
            type="number"
            value={budget}
            onChange={(e) => setBudget(Number(e.target.value))}
            style={{ width: 90 }}
          />
        </label>
        <button className="primary" onClick={() => loadAlloc(budget)}>
          Recommend
        </button>
        {alloc && (
          <span className="scanmsg">
            Buy {alloc.chosen.length} for {alloc.total_cost.display} → ~£
            {alloc.total_expected_profit.toFixed(2)} expected ({alloc.skipped_over_budget} skipped
            over budget)
          </span>
        )}
      </div>
      {alloc && <DealsTable deals={alloc.chosen} onBuy={onBuy} />}

      <h2>Holdings</h2>
      {msg && <p className="scanmsg">{msg}</p>}
      {pf && (
        <>
          <section className="stats">
            <div className="stat">
              <span className="figure">{pf.held}</span>
              <span className="label">held</span>
            </div>
            <div className="stat">
              <span className="figure">£{pf.invested.toFixed(2)}</span>
              <span className="label">invested</span>
            </div>
            <div className="stat">
              <span className={`figure ${pf.unrealised_pnl >= 0 ? "pos" : "neg"}`}>
                £{pf.unrealised_pnl.toFixed(2)}
              </span>
              <span className="label">unrealised P/L</span>
            </div>
            <div className="stat">
              <span className={`figure ${pf.realised_pnl >= 0 ? "pos" : "neg"}`}>
                £{pf.realised_pnl.toFixed(2)}
              </span>
              <span className="label">realised P/L (gross)</span>
            </div>
          </section>
          {pf.positions.length === 0 ? (
            <p className="empty">No holdings yet — hit “📌 Bought” on a deal.</p>
          ) : (
            <table className="srctable">
              <thead>
                <tr>
                  <th>Card</th>
                  <th className="r">Cost</th>
                  <th className="r">Value / sold</th>
                  <th className="c">Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {pf.positions.map((p) => (
                  <tr key={p.id}>
                    <td>{p.card}</td>
                    <td className="r">£{p.cost_basis.toFixed(2)}</td>
                    <td className="r">
                      {p.status === "SOLD" && p.sold_price != null
                        ? `sold £${p.sold_price.toFixed(2)}`
                        : `£${p.est_value.toFixed(2)}`}
                    </td>
                    <td className="c">
                      <span className={`badge ${p.status === "HELD" ? "no" : "ok"}`}>
                        {p.status}
                      </span>
                    </td>
                    <td>
                      {p.status === "HELD" && (
                        <button className="bought" onClick={() => onSell(p.id)}>
                          Mark sold
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </div>
  );
}
