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

function buyType(d: Deal): string {
  if (d.listing.buying_format === "AUCTION") {
    return "Auction";
  }
  return d.listing.accepts_best_offer ? "BIN + Offer" : "BIN";
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

// Names the *reason* a deal's valuation/economics is blank, so the user gets a
// real diagnosis instead of an opaque dash. Decision order matters: graded slabs
// need real sold comps; the free pokemontcg fallback explicitly can't price them.
function whyNoValuation(d: Deal): string {
  if (d.valuation) {
    return "Waiting on a fresh valuation — try a re-scan.";
  }
  if (d.is_graded) {
    return (
      "No sold comps for this graded slab. Add a RapidAPI key (Sources & Keys) for real " +
      "PSA/CGC prices, or turn on the Claude rough-estimate fallback."
    );
  }
  return (
    "No sold comps in the last 90 days for this exact query. Try a broader card name, " +
    "or wait for the free pokemontcg.io fallback (Sources & Keys → enable it)."
  );
}

function valuationLabel(d: Deal): string | null {
  if (!d.valuation) return null;
  if (d.valuation.provider === "claude_estimate") return "est. (rough)";
  if (d.valuation.provider === "pokemontcg_market") return "ref";
  return null;
}

export function DealsTable({
  deals,
  onBuy,
  watched,
  onToggleWatch,
}: {
  deals: Deal[];
  onBuy?: (id: string) => void;
  watched?: Set<string>;
  onToggleWatch?: (query: string, on: boolean) => void;
}) {
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
          <th>Lang.</th>
          <th>Type</th>
          <th className="r">Ask</th>
          <th className="r">Est. value</th>
          <th className="r">Profit</th>
          <th className="c">ROI</th>
          <th className="c">Disc.</th>
          <th className="c">Sell-through</th>
          <th className="c">Match</th>
          <th className="c">Status</th>
          <th className="c">Gem</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        {deals.map((d, i) => {
          const e = d.economics;
          const profitPos = e ? e.profit.amount >= 0 : false;
          const isAuction = d.listing.buying_format === "AUCTION";
          const ends = endsIn(d.listing.item_end_date);
          const askMoney =
            isAuction && d.listing.current_bid_price
              ? d.listing.current_bid_price
              : d.listing.price;
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
                  <div className="auction">
                    ⏳ Auction
                    {d.listing.bid_count != null
                      ? ` · ${d.listing.bid_count} bid${d.listing.bid_count === 1 ? "" : "s"}`
                      : ""}
                    {ends ? ` · ends in ${ends}` : ""}
                    {d.max_bid ? ` · max bid ${d.max_bid.display}` : ""}
                  </div>
                )}
                {!isAuction && d.listing.accepts_best_offer && (
                  <div className="auction">
                    💬 Offers{d.max_bid ? ` · offer up to ${d.max_bid.display}` : ""}
                  </div>
                )}
                {d.grading?.worth_grading && (
                  <div className="grade" title="Buy raw, grade it, sell the slab (expected value)">
                    🔼 Grade → +{d.grading.expected_profit.display} ({pct(d.grading.expected_roi)} EV)
                  </div>
                )}
                {d.hold_candidate && (
                  <div className="hold" title="Graded slab below market — long-term hold candidate">
                    💎 Hold{d.discount != null ? ` · ${pct(d.discount)} below market` : ""}
                  </div>
                )}
                {d.trend_pct != null && Math.abs(d.trend_pct) >= 0.05 && (
                  <div
                    className={d.trend_pct > 0 ? "trend up" : "trend down"}
                    title="Market-value momentum vs recent history"
                  >
                    {d.trend_pct > 0 ? "🔥" : "🔻"} {pct(d.trend_pct)}
                  </div>
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
              <td className={d.language === "English" ? "lang" : "lang foreign"}>
                {d.language === "English" ? "EN" : d.language}
              </td>
              <td className="btype">
                <span className="typebadge">{buyType(d)}</span>
                {isAuction && ends ? <div className="sub">⏳ {ends}</div> : null}
              </td>
              <td className="r">
                {askMoney.display}
                {d.listing.shipping && d.listing.shipping.amount > 0 ? (
                  <span className="sub"> +{d.listing.shipping.display}</span>
                ) : null}
              </td>
              <td className="r">
                {d.valuation ? (
                  <>
                    {d.valuation.median.display}
                    <span className="sub"> n={d.valuation.sample_size}</span>
                    {valuationLabel(d) && (
                      <div
                        className={`sub valbadge val-${d.valuation.provider}`}
                        title={
                          d.valuation.provider === "claude_estimate"
                            ? "Claude rough estimate — not a real comp"
                            : "pokemontcg.io market reference — not a real sold comp"
                        }
                      >
                        {valuationLabel(d)}
                      </div>
                    )}
                  </>
                ) : (
                  <span className="why" title={whyNoValuation(d)}>
                    —
                  </span>
                )}
              </td>
              <td className={`r ${e ? (profitPos ? "pos" : "neg") : ""}`}>
                {e ? e.profit.display : <span className="why" title={whyNoValuation(d)}>—</span>}
              </td>
              <td className="c">
                {e ? (
                  <>
                    <TrafficLight tier={d.profit_tier} title="Return on investment after fees">
                      {pct(e.roi)}
                    </TrafficLight>
                    {d.annualised_roi != null && (
                      <div className="sub" title="Annualised — ROI adjusted for how fast it sells">
                        ≈{pct(d.annualised_roi)}/yr
                      </div>
                    )}
                  </>
                ) : (
                  <span className="why" title={whyNoValuation(d)}>—</span>
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
                {d.valuation?.days_to_sell != null && (
                  <div className="sub" title="Estimated days to sell at market">
                    ~{Math.round(d.valuation.days_to_sell)}d
                  </div>
                )}
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
              <td className="c gemcell">
                {d.gem_score != null && d.gem_score > 0 ? (
                  <span className="gemchip" title={`Hidden-gem score ${d.gem_score.toFixed(1)} — high ROI vs. listing competition`}>
                    💎 {d.gem_score.toFixed(0)}
                  </span>
                ) : (
                  <span className="sub">—</span>
                )}
                {d.active_listings_count != null && (
                  <div className="sub" title="Active eBay listings for this card right now">
                    🏷️ {d.active_listings_count}
                  </div>
                )}
              </td>
              <td className="actions">
                {d.listing.url ? (
                  <a className="buy" href={d.listing.url} target="_blank" rel="noreferrer">
                    Open ↗
                  </a>
                ) : null}
                {onBuy && d.economics && (
                  <button
                    className="bought"
                    title="Mark as bought (track in portfolio)"
                    onClick={() => onBuy(d.id)}
                  >
                    📌 Bought
                  </button>
                )}
                {onToggleWatch && d.card && (() => {
                  const q = `${d.card!.name} ${d.card!.number}`;
                  const on = watched?.has(q) ?? false;
                  return (
                    <button
                      className={on ? "watchbtn watchbtn-on" : "watchbtn"}
                      title={on ? "Remove from My card list" : "Add to My card list — scan finds future deals"}
                      onClick={() => onToggleWatch(q, !on)}
                    >
                      {on ? "★ Watching" : "☆ Watch"}
                    </button>
                  );
                })()}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
