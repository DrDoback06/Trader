import { useEffect, useState } from "react";
import { fetchSources, setSourceEnabled, updateCredentials } from "../api";
import type { SourcesResponse } from "../types";

const KEY_FIELDS: { key: string; label: string; help: string }[] = [
  { key: "ebay_client_id", label: "eBay Client ID (App ID)", help: "https://developer.ebay.com/join/" },
  {
    key: "ebay_client_secret",
    label: "eBay Client Secret (Cert ID)",
    help: "https://developer.ebay.com/join/",
  },
  {
    key: "rapidapi_key",
    label: "RapidAPI key — eBay UK sold prices",
    help: "https://rapidapi.com/ecommet/api/ebay-average-selling-price",
  },
  {
    key: "pricecharting_api_key",
    label: "PriceCharting key (optional)",
    help: "https://www.pricecharting.com/api-documentation",
  },
];

export function SourcesPage() {
  const [data, setData] = useState<SourcesResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const load = () =>
    fetchSources()
      .then(setData)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load"));

  useEffect(() => {
    load();
  }, []);

  const save = async () => {
    const values = Object.fromEntries(Object.entries(form).filter(([, v]) => v.trim() !== ""));
    if (Object.keys(values).length === 0) {
      return;
    }
    setSaving(true);
    setMsg(null);
    try {
      setData(await updateCredentials(values));
      setForm({});
      setMsg("Saved — keys applied.");
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "save failed");
    } finally {
      setSaving(false);
    }
  };

  const toggle = async (id: string, enabled: boolean) => {
    try {
      await setSourceEnabled(id, enabled);
      load();
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "could not change source");
    }
  };

  if (error) {
    return <p className="error">{error}</p>;
  }
  if (!data) {
    return <p className="empty">Loading…</p>;
  }

  return (
    <div className="sources">
      <div className="note">🔒 {data.note}</div>

      <h2>Your API keys</h2>
      <p className="sub">
        Paste a key and click Save — it applies immediately. Current values are shown masked.
      </p>
      <div className="keys">
        {KEY_FIELDS.map((f) => (
          <div className="keyrow" key={f.key}>
            <label>{f.label}</label>
            <input
              type="password"
              placeholder={data.credentials[f.key] ?? "not set"}
              value={form[f.key] ?? ""}
              onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
            />
            <a href={f.help} target="_blank" rel="noreferrer">
              Where to get this ↗
            </a>
          </div>
        ))}
      </div>
      <div className="saverow">
        <button className="primary" onClick={save} disabled={saving}>
          {saving ? "Saving…" : "Save keys"}
        </button>
        {msg && <span className="scanmsg">{msg}</span>}
      </div>

      <h2>Price sources</h2>
      <p className="sub">
        Tick a source to include it. Only sources we trust for UK accuracy can be enabled — others
        are shown for transparency with the reason they're off.
      </p>
      <table className="srctable">
        <thead>
          <tr>
            <th className="c">Use</th>
            <th>Source</th>
            <th>Role</th>
            <th className="c">Region</th>
            <th>Notes</th>
            <th className="c">Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {data.sources.map((s) => (
            <tr key={s.id} className={s.available ? "" : "unavail"}>
              <td className="c">
                <input
                  type="checkbox"
                  checked={s.enabled}
                  disabled={!s.available}
                  title={s.available ? "" : `Not available: ${s.accuracy}`}
                  onChange={(e) => toggle(s.id, e.target.checked)}
                />
              </td>
              <td>{s.name}</td>
              <td className="sub">{s.role}</td>
              <td className="c">
                <span className={`region region-${s.region}`}>{s.region}</span>
              </td>
              <td className="sub">{s.accuracy}</td>
              <td className="c">
                {!s.available ? (
                  <span className="badge no">unavailable</span>
                ) : s.active ? (
                  <span className="badge ok">active</span>
                ) : s.configured ? (
                  <span className="badge no">off</span>
                ) : (
                  <span className="badge no">needs key</span>
                )}
              </td>
              <td>
                <a href={s.signup_url} target="_blank" rel="noreferrer">
                  {s.requires.length > 0 ? "Get key ↗" : "Info ↗"}
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
