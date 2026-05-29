import type { Deal } from "../types";
import { ConfidenceBadge } from "./ConfidenceBadge";
import { TrafficLight } from "./TrafficLight";

function pct(x: number): string {
  return `${Math.round(x * 100)}%`;
}

function condLabel(d: Deal): string {
  if (d.is_graded) {
    return d.grade ?? "Graded";
  }
  return d.condition.replace("RAW_", "");
}

function endsIn(iso: string | null): string | null {
  if (!iso) {
    return null;
  }
  const ms = new Date(iso).getTime() - Date.now();
  if (Number.isNaN(ms)) {
    return null;
  }
  if (ms <= 0) {
    return "ended";
  }
  const h = Math.floor(ms / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

export function DealsTable({ deals }: { deals: Deal[] }) {
  if (deals.length === 0) {
    return <p className="empty">No deals to show.</p>;
  }
  return (
    <table className="deals">
      <thead>
        <tr>
          <th className="num">#</th>
          <th>Card</th>
          <th>Cond.</th>
          <th className="r">Ask</th>
          <th className="r">Est. value</th>
          <th className="r">Profit</th>
          <th className="c">ROI</th>
          <th className="c">Disc.</th>
          <th className="c">Sell-through</th>
          <th className="c">Match</th>
          <th className="c">Status</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {deals.map((d, i) => {
          const e = d.economics;
          const profitPos = e ? e.profit.amount >= 0 : false;
          const isAuction = d.listing.buying_format === "AUCTION";
          const ends = endsIn(d.listing.item_end_date);
          return (
            <tr key={d.id} className={d.passed_rules ? "pass" : "skip"}>
              <td className="num">{i + 1}</td>
              <td className="cardcell">
                <div className="name">
                  {d.card ? d.card.name : "(no match)"}
                  {d.card ? <span className="cardno"> {d.card.number}</span> : null}
                </div>
                <div className="sub">{d.card ? d.card.set_name : d.listing.title}</div>
                {isAuction && (
                  <div className="auction">⏳ Auction{ends ? ` · ends in ${ends}` : ""}</div>
                )}
                {d.flags.length > 0 && (
                  <div className="flags">
                    {d.flags.map((f) => (
                      <span key={f} className="flag">
                        {f}
                      </span>
                    ))}
                  </div>
                )}
              </td>
              <td>{condLabel(d)}</td>
              <td className="r">
                {d.listing.price.display}
                {d.listing.shipping && d.listing.shipping.amount > 0 ? (
                  <span className="sub"> +{d.listing.shipping.display}</span>
                ) : null}
              </td>
              <td className="r">
                {d.valuation ? (
                  <>
                    {d.valuation.median.display}
                    <span className="sub"> n={d.valuation.sample_size}</span>
                  </>
                ) : (
                  "—"
                )}
              </td>
              <td className={`r ${e ? (profitPos ? "pos" : "neg") : ""}`}>
                {e ? e.profit.display : "—"}
              </td>
              <td className="c">
                {e ? (
                  <TrafficLight tier={d.profit_tier} title="Return on investment after fees">
                    {pct(e.roi)}
                  </TrafficLight>
                ) : (
                  "—"
                )}
              </td>
              <td className="c sub">{d.discount != null ? pct(d.discount) : "—"}</td>
              <td className="c">
                <TrafficLight
                  tier={d.sell_tier}
                  title="Rough chance it sells near market value (liquidity + price stability)"
                >
                  {pct(d.sell_probability)}
                </TrafficLight>
              </td>
              <td className="c">
                <ConfidenceBadge value={d.confidence} />
              </td>
              <td className="c">
                {d.passed_rules ? (
                  <span className="badge ok">BUY</span>
                ) : (
                  <span className="badge no" title={d.rule_reasons.join("; ")}>
                    skip
                  </span>
                )}
              </td>
              <td>
                {d.listing.url ? (
                  <a className="buy" href={d.listing.url} target="_blank" rel="noreferrer">
                    Open ↗
                  </a>
                ) : null}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
