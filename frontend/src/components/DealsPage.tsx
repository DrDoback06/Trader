import { useCallback, useEffect, useMemo, useState } from "react";
import {
  addCard,
  buyDeal,
  evaluateCard,
  fetchCards,
  fetchDeals,
  removeCard,
  scanCards,
  searchCardListings,
} from "../api";
import type { Deal } from "../types";
import { DealsTable } from "./DealsTable";
import { ValuationStatusBanner } from "./ValuationStatusBanner";

// Total you'd pay right now (current bid for auctions, else price) + postage.
function effAsk(d: Deal): number {
  const base =
    d.listing.buying_format === "AUCTION" && d.listing.current_bid_price
      ? d.listing.current_bid_price.amount
      : d.listing.price.amount;
  return base + (d.listing.shipping?.amount ?? 0);
}

function endTs(d: Deal): number {
  if (!d.listing.item_end_date) {
    return Number.POSITIVE_INFINITY;
  }
  const t = new Date(d.listing.item_end_date).getTime();
  return Number.isNaN(t) ? Number.POSITIVE_INFINITY : t;
}

const SORTERS: Record<string, (a: Deal, b: Deal) => number> = {
  best: (a, b) => b.score - a.score,
  ending: (a, b) => endTs(a) - endTs(b),
  price: (a, b) => effAsk(a) - effAsk(b),
  roi: (a, b) => (b.economics?.roi ?? -Infinity) - (a.economics?.roi ?? -Infinity),
  discount: (a, b) => (b.discount ?? -Infinity) - (a.discount ?? -Infinity),
  sell: (a, b) => b.sell_probability - a.sell_probability,
};

export function DealsPage({
  prefillQuery = null,
  onPrefillConsumed,
}: {
  prefillQuery?: string | null;
  onPrefillConsumed?: () => void;
} = {}) {
  const [deals, setDeals] = useState<Deal[]>([]);
  const [onlyPassing, setOnlyPassing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanMsg, setScanMsg] = useState<string | null>(null);
  const [valueCap, setValueCap] = useState(250);
  const [scanned, setScanned] = useState(false);
  const [hideSamples, setHideSamples] = useState(false);

  // The user's saved card list — the scan button runs a live per-card search for each.
  const [cards, setCards] = useState<string[]>([]);

  // eBay-style filter / sort of the results (client-side).
  const [sortBy, setSortBy] = useState("best");
  const [fType, setFType] = useState("all");
  const [fCond, setFCond] = useState("all");
  const [fLang, setFLang] = useState("all");
  const [fMax, setFMax] = useState("");

  // "Check a card" — a real valuation using your live sold-price key, no eBay key needed.
  const [checks, setChecks] = useState<Deal[]>([]);
  const [cardQuery, setCardQuery] = useState("");
  const [askPrice, setAskPrice] = useState("");
  const [postage, setPostage] = useState("");
  const [checking, setChecking] = useState(false);
  const [checkMsg, setCheckMsg] = useState<string | null>(null);
  // "Search live listings" — a real eBay keyword search for the card in the box.
  // One smart search: it reads the grade from each listing and auto-tries misspellings.
  const [searching, setSearching] = useState(false);

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

  // Load the saved card list once.
  useEffect(() => {
    fetchCards()
      .then((r) => setCards(r.cards))
      .catch(() => setCards([]));
  }, []);

  // A card picked in the Browse tab pre-fills the box, runs the live search for it, and
  // adds it to the saved list — so tapping a card in Browse both shows its real listings
  // and remembers it for the next batch scan.
  useEffect(() => {
    if (prefillQuery) {
      setCardQuery(prefillQuery);
      onSearchCard(prefillQuery);
      onAddCard(prefillQuery);
      onPrefillConsumed?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prefillQuery]);

  // The scan button: run the saved card list as a batch of live per-card searches.
  const onScan = async () => {
    if (cards.length === 0) {
      setScanMsg("Your card list is empty — add cards below (or pick one from Browse).");
      return;
    }
    setScanning(true);
    setScanMsg(null);
    try {
      const r = await scanCards({ max_valuations: valueCap });
      const errs = r.errors ?? [];
      const warn = errs.length ? ` ⚠️ ${errs.join(" · ")}` : "";
      setScanMsg(
        `Searched ${r.targets_scanned} card(s) · ${r.listings_seen} live listing(s) · valued ${
          r.valued ?? r.new_listings
        }${r.quota_exhausted ? " (daily call budget hit)" : ""}.` + warn,
      );
      // Only suppress the bundled demo rows once the live scan actually produced
      // valuations — otherwise the user is left with a blank page and no signal.
      if ((r.valued ?? 0) > 0) {
        setScanned(true);
        setHideSamples(false);
      }
      load();
    } catch (err: unknown) {
      setScanMsg(err instanceof Error ? err.message : "scan failed");
    } finally {
      setScanning(false);
    }
  };

  const onAddCard = async (query: string) => {
    const q = query.trim();
    if (q.length < 3) return;
    try {
      const r = await addCard(q);
      setCards(r.cards);
      setScanMsg(`★ Added "${q}" to your card list.`);
    } catch {
      /* already in the list — ignore */
    }
  };

  const onRemoveCard = async (query: string) => {
    try {
      const r = await removeCard(query);
      setCards(r.cards);
    } catch {
      /* ignore */
    }
  };

  const watched = useMemo(() => new Set(cards), [cards]);
  const toggleWatch = (query: string, on: boolean) => {
    if (on) onAddCard(query);
    else onRemoveCard(query);
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

  const onSearchCard = async (queryOverride?: string) => {
    const q = (queryOverride ?? cardQuery).trim();
    if (q.length < 3) {
      setCheckMsg("Type or pick a card to search (3+ characters).");
      return;
    }
    setSearching(true);
    setCheckMsg(null);
    setScanMsg(null);
    try {
      const r = await searchCardListings({ query: q });
      const errs = r.errors ?? [];
      setScanMsg(
        `Found ${r.listings_seen} live listing(s) for “${q}”${
          r.valued ? ` · valued ${r.valued}` : ""
        }.` + (errs.length ? ` ⚠️ ${errs.join(" · ")}` : ""),
      );
      // Same rule as the batch scan: don't tear the samples down unless we got real valuations.
      if ((r.valued ?? 0) > 0) {
        setScanned(true);
        setHideSamples(false);
      }
      load();
    } catch (err: unknown) {
      setCheckMsg(err instanceof Error ? err.message : "search failed");
    } finally {
      setSearching(false);
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

  const showSamples = !scanned && !hideSamples && deals.length > 0;

  const visible = useMemo(() => {
    const maxP = Number(fMax);
    const xs = deals.filter((d) => {
      if (fType === "auction" && d.listing.buying_format !== "AUCTION") return false;
      if (fType === "bin" && d.listing.buying_format !== "FIXED_PRICE") return false;
      if (fType === "offer" && !d.listing.accepts_best_offer) return false;
      if (fCond === "graded" && !d.is_graded) return false;
      if (fCond === "raw" && d.is_graded) return false;
      if (fLang === "en" && d.language !== "English") return false;
      if (fLang === "foreign" && d.language === "English") return false;
      if (Number.isFinite(maxP) && maxP > 0 && effAsk(d) > maxP) return false;
      return true;
    });
    // Stable tiebreaker (id) so the order is deterministic even when the primary key
    // ties — e.g. before valuations land and every score/ROI is 0.
    return [...xs].sort((a, b) => (SORTERS[sortBy] ?? SORTERS.best)(a, b) || a.id.localeCompare(b.id));
  }, [deals, fType, fCond, fLang, fMax, sortBy]);

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
      <ValuationStatusBanner />
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
          Type a card the way you'd search eBay (or pick one from Browse). <strong>Check value</strong>{" "}
          prices one purchase against UK sold data; <strong>Search live listings</strong> pulls every
          live eBay listing of that card and ranks the underpriced ones — raw and graded alike (it
          reads the grade from each listing; type "PSA 10" to focus on slabs).
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
          <button className="bought" onClick={() => onSearchCard()} disabled={searching}>
            {searching ? "Searching…" : "🔎 Search live listings"}
          </button>
          <button
            className="bought watchbtn"
            onClick={() => onAddCard(cardQuery)}
            disabled={cardQuery.trim().length < 3}
            title="Add this card to the list the scan button searches"
          >
            ★ Watch this card
          </button>
          {checkMsg && <span className="scanmsg">{checkMsg}</span>}
        </div>
        {checks.length > 0 && (
          <>
            <DealsTable
              deals={checks}
              onBuy={onBuy}
              watched={watched}
              onToggleWatch={toggleWatch}
            />
            <button className="linkbtn" onClick={() => setChecks([])}>
              Clear checks
            </button>
          </>
        )}
      </div>

      <div className="cardlist">
        <h2>My card list</h2>
        <p className="sub">
          The scan button runs a live eBay search for <strong>each</strong> of these cards and ranks
          the underpriced ones — no marketplace-wide junk, just the cards you care about. Add cards
          here, from <strong>Browse</strong>, or with <strong>➕ List</strong> in “Check a card”.
        </p>
        <div className="chips">
          {cards.length === 0 && <span className="muted">No cards yet — add some below.</span>}
          {cards.map((c) => (
            <span key={c} className="chip">
              {c}
              <button
                className="chipx"
                title="Remove from list"
                onClick={() => onRemoveCard(c)}
              >
                ×
              </button>
            </span>
          ))}
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
            Value up to
            <input
              type="number"
              min="1"
              max="250"
              value={valueCap}
              onChange={(e) =>
                setValueCap(Math.max(1, Math.min(250, Number(e.target.value) || 1)))
              }
              style={{ width: 64 }}
              title="Per card: how many of the cheapest listings to fetch a live value for (caps API calls)"
            />
          </label>

          <button
            className="primary"
            onClick={onScan}
            disabled={scanning || cards.length === 0}
          >
            {scanning ? "Scanning…" : `↻ Scan my ${cards.length} card(s)`}
          </button>
          {scanMsg && <span className="scanmsg">{scanMsg}</span>}
        </div>
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

      {!loading && !error && !hideSamples && deals.length > 0 && (
        <div className="controls filterbar">
          <label className="field">
            Sort
            <select value={sortBy} onChange={(e) => setSortBy(e.target.value)}>
              <option value="best">Best match</option>
              <option value="ending">Ending soonest</option>
              <option value="price">Price + P&amp;P: low → high</option>
              <option value="roi">Highest ROI</option>
              <option value="discount">Biggest discount</option>
              <option value="sell">Best sell-through</option>
            </select>
          </label>
          <label className="field">
            Type
            <select value={fType} onChange={(e) => setFType(e.target.value)}>
              <option value="all">All listings</option>
              <option value="bin">Buy It Now</option>
              <option value="offer">Accepts offers</option>
              <option value="auction">Auction</option>
            </select>
          </label>
          <label className="field">
            Condition
            <select value={fCond} onChange={(e) => setFCond(e.target.value)}>
              <option value="all">Any</option>
              <option value="raw">Raw</option>
              <option value="graded">Graded</option>
            </select>
          </label>
          <label className="field">
            Language
            <select value={fLang} onChange={(e) => setFLang(e.target.value)}>
              <option value="all">Any</option>
              <option value="en">English only</option>
              <option value="foreign">Non-English</option>
            </select>
          </label>
          <label className="field">
            Max £ (inc P&amp;P)
            <input
              type="number"
              min="0"
              step="1"
              value={fMax}
              onChange={(e) => setFMax(e.target.value)}
            />
          </label>
          <span className="spacer" />
          <span className="count">
            {visible.length} of {deals.length}
          </span>
        </div>
      )}

      {loading && <p className="empty">Loading…</p>}
      {error && (
        <p className="error">
          {error}. Is the backend running on <code>http://localhost:8000</code>?
        </p>
      )}
      {!loading && !error && !hideSamples && deals.length > 0 && (
        <DealsTable deals={visible} onBuy={onBuy} watched={watched} onToggleWatch={toggleWatch} />
      )}
      {!loading && !error && !hideSamples && deals.length === 0 && (
        <p className="empty">
          No deals loaded — run a live eBay scan above (your eBay keys are in 🎉), or use “Check a
          card”.
        </p>
      )}
      {!loading && !error && hideSamples && !scanned && (
        <p className="empty">
          Samples hidden. Use “Check a card” above, or run a live scan once your eBay keys are in.
        </p>
      )}
    </>
  );
}
