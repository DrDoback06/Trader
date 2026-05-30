import { useEffect, useState } from "react";
import {
  clearCredential,
  fetchSources,
  setSourceEnabled,
  testEbayKeys,
  updateCredentials,
} from "../api";
import type { SourcesResponse } from "../types";

const KEY_FIELDS: { key: string; label: string; help: string }[] = [
  { key: "ebay_client_id", label: "eBay Client ID (App ID — must contain PRD)", help: "https://developer.ebay.com/my/keys" },
  {
    key: "ebay_client_secret",
    label: "eBay Client Secret (Cert ID — Production)",
    help: "https://developer.ebay.com/my/keys",
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
  {
    key: "anthropic_api_key",
    label: "Claude API key — photo card ID (optional)",
    help: "https://console.anthropic.com/",
  },
  {
    key: "ebay_user_token",
    label: "eBay seller token — relisting (optional, sell.inventory scope)",
    help: "https://developer.ebay.com/api-docs/static/oauth-tokens.html",
  },
  {
    key: "telegram_bot_token",
    label: "Telegram bot token — alerts (optional)",
    help: "https://core.telegram.org/bots#how-do-i-create-a-bot",
  },
  {
    key: "telegram_chat_id",
    label: "Telegram chat ID — alerts (optional)",
    help: "https://t.me/userinfobot",
  },
];

export function SourcesPage() {
  const [data, setData] = useState<SourcesResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [testing, setTesting] = useState(false);
  const [testMsg, setTestMsg] = useState<string | null>(null);

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
      setMsg("Nothing to save — type a key into a box first.");
      return;
    }
    setSaving(true);
    setMsg(null);
    try {
      setData(await updateCredentials(values));
      setForm({});
      setMsg(`Saved ${Object.keys(values).length} key(s) — applied.`);
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "save failed");
    } finally {
      setSaving(false);
    }
  };

  const clearKey = async (key: string) => {
    setMsg(null);
    try {
      setData(await clearCredential(key));
      setForm((f) => ({ ...f, [key]: "" }));
      setMsg("Cleared.");
    } catch (e: unknown) {
      setMsg(e instanceof Error ? e.message : "could not clear");
    }
  };

  const testEbay = async () => {
    setTesting(true);
    setTestMsg(null);
    try {
      const r = await testEbayKeys();
      setTestMsg((r.ok ? "✅ " : "❌ ") + r.detail);
    } catch (e: unknown) {
      setTestMsg(e instanceof Error ? e.message : "test failed");
    } finally {
      setTesting(false);
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
        Type or paste a key (shown so you can check it) and click <strong>Save keys</strong> — it
        applies immediately and overwrites whatever was there. Use <strong>Clear</strong> to wipe a
        key. Leaving a box empty keeps the current value.
      </p>
      <div className="keys">
        {KEY_FIELDS.map((f) => {
          const current = data.credentials[f.key];
          return (
            <div className="keyrow wide" key={f.key}>
              <label>{f.label}</label>
              <input
                type="text"
                autoComplete="off"
                autoCorrect="off"
                autoCapitalize="off"
                spellCheck={false}
                name={`trader_${f.key}`}
                placeholder={current ? `current: ${current}` : "not set"}
                value={form[f.key] ?? ""}
                onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
              />
              <span className="cur">{current ? `now: ${current}` : "not set"}</span>
              <a href={f.help} target="_blank" rel="noreferrer">
                Where to get this ↗
              </a>
              <button className="linkbtn" disabled={!current} onClick={() => clearKey(f.key)}>
                Clear
              </button>
            </div>
          );
        })}
      </div>
      <div className="saverow">
        <button className="primary" onClick={save} disabled={saving}>
          {saving ? "Saving…" : "Save keys"}
        </button>
        <button className="bought" onClick={testEbay} disabled={testing}>
          {testing ? "Testing…" : "Test eBay keys"}
        </button>
        {msg && <span className="scanmsg">{msg}</span>}
        {testMsg && <span className="scanmsg">{testMsg}</span>}
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
