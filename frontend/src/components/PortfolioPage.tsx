import { Fragment, useEffect, useMemo, useState } from "react";
import { buyDeal, fetchAllocation, fetchPortfolio, relistPreview, sellPosition } from "../api";
import type { Allocation, Portfolio, Position } from "../types";
import { DealsTable } from "./DealsTable";

function variantLabel(p: Position): string {
  if (p.grade) {
    return p.grade;
  }
  return p.condition ? p.condition.replace("RAW_", "") : "—";
}

// What the copy is currently "worth" for P/L: sold price if sold, else market est.
function outValue(p: Position): number {
  return p.status === "SOLD" && p.sold_price != null ? p.sold_price : p.est_value;
}

function pnl(p: Position): number {
  return outValue(p) - p.cost_basis;
}

function money(n: number): string {
  return `${n < 0 ? "-" : ""}£${Math.abs(n).toFixed(2)}`;
}

interface SetGroup {
  name: string;
  cards: { key: string; copies: Position[] }[];
  count: number;
  cost: number;
  value: number;
}

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

  const onRelist = async (id: number) => {
    try {
      const r = await relistPreview(id);
      setMsg(`Relist draft → "${r.preview.title}" @ ${r.preview.price.display}. ${r.note}`);
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "could not build relist draft");
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

  // Group holdings: Set -> Card (name + number) -> individual copies.
  const groups = useMemo<SetGroup[]>(() => {
    if (!pf) {
      return [];
    }
    const bySet = new Map<string, Map<string, Position[]>>();
    for (const p of pf.positions) {
      const set = p.set_name || "Unknown set";
      const card = `${p.card_name}${p.number ? ` ${p.number}` : ""}`;
      const cards = bySet.get(set) ?? new Map<string, Position[]>();
      const copies = cards.get(card) ?? [];
      copies.push(p);
      cards.set(card, copies);
      bySet.set(set, cards);
    }
    return [...bySet.entries()].map(([name, cards]) => {
      const cardList = [...cards.entries()].map(([key, copies]) => ({ key, copies }));
      const all = cardList.flatMap((c) => c.copies);
      return {
        name,
        cards: cardList,
        count: all.length,
        cost: all.reduce((s, p) => s + p.cost_basis, 0),
        value: all.reduce((s, p) => s + outValue(p), 0),
      };
    });
  }, [pf]);

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
            <p className="empty">No holdings yet — hit “📌 Bought” on a deal or a checked card.</p>
          ) : (
            <table className="srctable holdings">
              <thead>
                <tr>
                  <th>Set / card / copy</th>
                  <th className="c">Status</th>
                  <th className="r">Cost</th>
                  <th className="r">Value / sold</th>
                  <th className="r">P/L</th>
                  <th></th>
                </tr>
              </thead>
              {groups.map((g) => (
                <tbody key={g.name}>
                  <tr className="setrow">
                    <td>📦 {g.name}</td>
                    <td className="c">{g.count}</td>
                    <td className="r">£{g.cost.toFixed(2)}</td>
                    <td className="r">£{g.value.toFixed(2)}</td>
                    <td className={`r ${g.value - g.cost >= 0 ? "pos" : "neg"}`}>
                      {money(g.value - g.cost)}
                    </td>
                    <td></td>
                  </tr>
                  {g.cards.map((c) => (
                    <Fragment key={c.key}>
                      <tr className="cardrow">
                        <td colSpan={6}>
                          {c.key} · {c.copies.length} cop{c.copies.length === 1 ? "y" : "ies"}
                        </td>
                      </tr>
                      {c.copies.map((p) => (
                        <tr key={p.id}>
                          <td className="variant">{variantLabel(p)}</td>
                          <td className="c">
                            <span className={`badge ${p.status === "HELD" ? "no" : "ok"}`}>
                              {p.status}
                            </span>
                          </td>
                          <td className="r">£{p.cost_basis.toFixed(2)}</td>
                          <td className="r">
                            {p.status === "SOLD" && p.sold_price != null
                              ? `sold £${p.sold_price.toFixed(2)}`
                              : `£${p.est_value.toFixed(2)}`}
                          </td>
                          <td className={`r ${pnl(p) >= 0 ? "pos" : "neg"}`}>{money(pnl(p))}</td>
                          <td className="actions">
                            {p.status === "HELD" && (
                              <button className="bought" onClick={() => onRelist(p.id)}>
                                Relist
                              </button>
                            )}
                            {p.status !== "SOLD" && (
                              <button className="bought" onClick={() => onSell(p.id)}>
                                Mark sold
                              </button>
                            )}
                            {p.url && (
                              <a className="buy" href={p.url} target="_blank" rel="noreferrer">
                                Open ↗
                              </a>
                            )}
                          </td>
                        </tr>
                      ))}
                    </Fragment>
                  ))}
                </tbody>
              ))}
            </table>
          )}
        </>
      )}
    </div>
  );
}
