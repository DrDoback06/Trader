import { useEffect, useState } from "react";
import { fetchAlertStatus, fetchRules, setSchedule, testAlert, updateRules } from "../api";
import type { AlertStatus } from "../api";
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
  { key: "min_sell_probability", label: "Min sell-through (%)", hint: "0 = ignore liquidity" },
  { key: "min_annualised_roi", label: "Min annualised ROI (%)", hint: "0 = ignore turnover speed" },
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

  // Auto-scan & alerts
  const [status, setStatus] = useState<AlertStatus | null>(null);
  const [intervalMin, setIntervalMin] = useState("0");
  const [busy, setBusy] = useState(false);
  const [alertMsg, setAlertMsg] = useState<string | null>(null);

  useEffect(() => {
    fetchRules()
      .then((r) => {
        setRules(r.rules);
        setForm(formFromRules(r.rules));
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load"));
    fetchAlertStatus()
      .then((s) => {
        setStatus(s);
        setIntervalMin(String(s.interval_min));
      })
      .catch(() => undefined);
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

  const onApplySchedule = async () => {
    setBusy(true);
    setAlertMsg(null);
    try {
      setStatus(await setSchedule(Math.max(0, Number(intervalMin) || 0)));
      setAlertMsg("Updated.");
    } catch (e: unknown) {
      setAlertMsg(e instanceof Error ? e.message : "could not update");
    } finally {
      setBusy(false);
    }
  };

  const onTest = async () => {
    setAlertMsg(null);
    try {
      const r = await testAlert();
      setAlertMsg(`Test sent via ${r.channel}.`);
    } catch (e: unknown) {
      setAlertMsg(e instanceof Error ? e.message : "test failed");
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

      <h2>Auto-scan &amp; alerts</h2>
      <p className="sub">
        Scan automatically every few minutes and get pushed the new green deals. On this laptop it
        only runs while the app is open — deploy to a host for 24/7. Add a Telegram bot token + chat
        ID under <strong>Sources &amp; Keys</strong> for phone alerts (otherwise alerts print to the
        server log).
      </p>
      <div className="controls">
        <label className="field">
          Scan every (min, 0 = off)
          <input
            type="number"
            min="0"
            step="1"
            value={intervalMin}
            onChange={(e) => setIntervalMin(e.target.value)}
            style={{ width: 80 }}
          />
        </label>
        <button className="primary" onClick={onApplySchedule} disabled={busy}>
          {busy ? "Applying…" : "Apply"}
        </button>
        <button className="bought" onClick={onTest}>
          Send test alert
        </button>
        {status && (
          <span className="scanmsg">
            {status.running ? `ON · every ${status.interval_min} min` : "off"} · channel:{" "}
            {status.channel}
          </span>
        )}
        {alertMsg && <span className="scanmsg">{alertMsg}</span>}
      </div>
      <p className="note">
        ⚠️ Each auto-scan uses your eBay + sold-price quota. Keep the interval sensible (e.g. 15–30
        min) and the “Value up to” cap modest.
      </p>
    </div>
  );
}
