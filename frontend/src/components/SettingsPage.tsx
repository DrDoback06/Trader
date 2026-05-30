import { useEffect, useState } from "react";
import { fetchRules, updateRules } from "../api";
import type { Rules } from "../types";

const MONEY = [
  { key: "total_budget", label: "Total budget (£)", hint: "Your working capital" },
  { key: "max_spend_per_card", label: "Max spend per card (£)", hint: "Skip anything dearer" },
  { key: "min_profit", label: "Min profit (£)", hint: "Don't bother below this" },
] as const;

const PCT = [
  { key: "min_roi", label: "Min ROI (%)", hint: "Profit ÷ cost, after fees" },
  { key: "min_margin", label: "Min margin (%)", hint: "Profit ÷ sale price" },
  { key: "min_confidence", label: "Min match confidence (%)", hint: "How sure the card ID is" },
  { key: "min_discount", label: "Min discount vs market (%)", hint: "How far below market to buy" },
  { key: "min_sell_probability", label: "Min sell-through (%)", hint: "0 = don't filter by liquidity" },
  { key: "min_annualised_roi", label: "Min annualised ROI (%)", hint: "0 = don't require fast turnover" },
] as const;

function formFromRules(r: Rules): Record<string, string> {
  return {
    total_budget: String(r.total_budget.amount),
    max_spend_per_card: String(r.max_spend_per_card.amount),
    min_profit: String(r.min_profit.amount),
    min_roi: String(Math.round(r.min_roi * 100)),
    min_margin: String(Math.round(r.min_margin * 100)),
    min_confidence: String(Math.round(r.min_confidence * 100)),
    min_discount: String(Math.round(r.min_discount * 100)),
    min_sell_probability: String(Math.round(r.min_sell_probability * 100)),
    min_annualised_roi: String(Math.round(r.min_annualised_roi * 100)),
  };
}

export function SettingsPage() {
  const [rules, setRules] = useState<Rules | null>(null);
  const [form, setForm] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchRules()
      .then((r) => {
        setRules(r.rules);
        setForm(formFromRules(r.rules));
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load"));
  }, []);

  const onSave = async () => {
    setSaving(true);
    setMsg(null);
    try {
      const patch: Record<string, number> = {};
      for (const m of MONEY) {
        patch[m.key] = Math.max(0, Number(form[m.key]) || 0);
      }
      for (const p of PCT) {
        patch[p.key] = Math.max(0, Number(form[p.key]) || 0) / 100;
      }
      const r = await updateRules(patch);
      setRules(r.rules);
      setForm(formFromRules(r.rules));
      setMsg("Saved — applies to your next scan.");
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "save failed");
    } finally {
      setSaving(false);
    }
  };

  if (error) {
    return <p className="error">{error}</p>;
  }
  if (!rules) {
    return <p className="empty">Loading…</p>;
  }

  return (
    <div className="sources">
      <h2>Your buy rules</h2>
      <p className="sub">
        These decide which deals get the green <strong>BUY</strong> stamp. They never hide
        listings — every scanned card is still shown and ranked; the rules just flag what clears
        your limits. Changes apply to your next scan.
      </p>
      <div className="keys">
        {MONEY.map((f) => (
          <div className="keyrow" key={f.key}>
            <label>{f.label}</label>
            <input
              type="number"
              min="0"
              step="0.01"
              value={form[f.key] ?? ""}
              onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
            />
            <span className="sub">{f.hint}</span>
          </div>
        ))}
        {PCT.map((f) => (
          <div className="keyrow" key={f.key}>
            <label>{f.label}</label>
            <input
              type="number"
              min="0"
              step="1"
              value={form[f.key] ?? ""}
              onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
            />
            <span className="sub">{f.hint}</span>
          </div>
        ))}
      </div>
      <div className="saverow">
        <button className="primary" onClick={onSave} disabled={saving}>
          {saving ? "Saving…" : "Save rules"}
        </button>
        {msg && <span className="scanmsg">{msg}</span>}
      </div>
      <p className="note">
        Tip: to “pull everything and just see the best,” keep these modest and rely on the
        ranking + the “Only deals that clear my buy rules” toggle on the Deals tab.
      </p>
    </div>
  );
}
