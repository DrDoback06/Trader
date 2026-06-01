import { useEffect, useMemo, useState } from "react";
import {
  addCollectionListing,
  fetchCollection,
  fetchSealed,
  fetchSetCards,
  fetchSets,
  importEbayListings,
  removeCollectionListing,
  updateCollectionCard,
} from "../api";
import type { CatalogueCard, CollectionEntry, SealedPreset, SetInfo } from "../types";

const EMPTY: CollectionEntry = {
  owned: 0,
  condition: "",
  paid: null,
  target_price: null,
  for_sale: false,
  notes: "",
  listings: [],
};

export function BrowsePage({ onPick }: { onPick: (query: string) => void }) {
  const [sets, setSets] = useState<SetInfo[]>([]);
  const [total, setTotal] = useState(0);
  const [active, setActive] = useState<SetInfo | null>(null);
  const [cards, setCards] = useState<CatalogueCard[]>([]);
  const [loadingCards, setLoadingCards] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [setFilter, setSetFilter] = useState("");
  const [cardFilter, setCardFilter] = useState("");
  const [tab, setTab] = useState<"sets" | "sealed">("sets");
  const [sealed, setSealed] = useState<SealedPreset[]>([]);

  // The owned-card collection, keyed by card id, overlaid on the tiles.
  const [collection, setCollection] = useState<Record<string, CollectionEntry>>({});
  const [openCard, setOpenCard] = useState<string | null>(null);
  const [importMsg, setImportMsg] = useState<string | null>(null);
  const [ownedOnly, setOwnedOnly] = useState(false);

  useEffect(() => {
    fetchSets()
      .then((r) => {
        setSets(r.sets);
        setTotal(r.total_cards);
      })
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load sets"));
    fetchSealed()
      .then((r) => setSealed(r.sealed))
      .catch(() => setSealed([]));
    fetchCollection()
      .then((r) => setCollection(r.cards))
      .catch(() => setCollection({}));
  }, []);

  const openSet = (s: SetInfo) => {
    setActive(s);
    setCards([]);
    setCardFilter("");
    setLoadingCards(true);
    fetchSetCards(s.set_code)
      .then((r) => setCards(r.cards))
      .catch((e: unknown) => setError(e instanceof Error ? e.message : "failed to load cards"))
      .finally(() => setLoadingCards(false));
  };

  const onImportEbay = async () => {
    setImportMsg("Importing your eBay listings…");
    try {
      const r = await importEbayListings();
      setImportMsg(
        `Found ${r.found} eBay listing(s), matched ${r.matched} to cards.` +
          (r.note ? ` ${r.note}` : ""),
      );
      const fresh = await fetchCollection();
      setCollection(fresh.cards);
    } catch (e: unknown) {
      setImportMsg(e instanceof Error ? e.message : "import failed");
    }
  };

  const patchCard = async (
    cardId: string,
    patch: Partial<Omit<CollectionEntry, "listings">>,
  ) => {
    const updated = await updateCollectionCard(cardId, patch);
    setCollection((prev) => ({ ...prev, [cardId]: updated }));
  };

  const visibleSets = useMemo(
    () => sets.filter((s) => s.set_name.toLowerCase().includes(setFilter.toLowerCase())),
    [sets, setFilter],
  );
  const visibleCards = useMemo(
    () =>
      cards.filter((c) => {
        if (ownedOnly && !(collection[c.id]?.owned > 0)) return false;
        return `${c.name} ${c.number}`.toLowerCase().includes(cardFilter.toLowerCase());
      }),
    [cards, cardFilter, ownedOnly, collection],
  );

  if (error) {
    return <p className="error">{error}</p>;
  }

  // --- set / sealed picker (no set open) ---
  if (!active) {
    return (
      <div className="browse">
        <div className="controls">
          <button
            className={tab === "sets" ? "tab active" : "tab"}
            onClick={() => setTab("sets")}
          >
            Sets &amp; cards
          </button>
          <button
            className={tab === "sealed" ? "tab active" : "tab"}
            onClick={() => setTab("sealed")}
          >
            Sealed product
          </button>
          <span className="spacer" />
          <button className="bought" onClick={onImportEbay} title="Pull your active eBay listings">
            ⇪ Import my eBay listings
          </button>
        </div>
        {importMsg && <p className="sub">{importMsg}</p>}

        {tab === "sealed" ? (
          <>
            <h2>Sealed product</h2>
            <p className="sub">
              Boxes, ETBs and bundles aren’t single cards — tap one to search live eBay listings
              for it and value them.
            </p>
            <div className="sealedgrid">
              {sealed.map((s) => (
                <button key={s.query} className="sealedtile" onClick={() => onPick(s.query)}>
                  📦 {s.label}
                </button>
              ))}
            </div>
          </>
        ) : (
          <>
            <h2>Browse the catalogue</h2>
            <p className="sub">
              {total.toLocaleString()} cards across {sets.length} sets. Tap a set, then a card to
              value it, mark it owned, or add your listings.{" "}
              {total < 100 &&
                "Only the bundled sample sets are loaded — run ./run.bat --catalogue once for every set + card images."}
            </p>
            <div className="controls">
              <label className="field grow">
                Find a set
                <input
                  type="text"
                  value={setFilter}
                  placeholder="e.g. 151, Obsidian, Base"
                  onChange={(e) => setSetFilter(e.target.value)}
                />
              </label>
            </div>
            <div className="settiles">
              {visibleSets.map((s) => (
                <button key={s.set_code} className="settile" onClick={() => openSet(s)}>
                  {s.image ? (
                    <img src={s.image} alt="" loading="lazy" />
                  ) : (
                    <div className="setcode">{s.set_code}</div>
                  )}
                  <div className="setname">{s.set_name}</div>
                  <div className="sub">{s.count} cards</div>
                </button>
              ))}
            </div>
          </>
        )}
      </div>
    );
  }

  // --- cards within a set ---
  return (
    <div className="browse">
      <div className="controls">
        <button className="linkbtn" onClick={() => setActive(null)}>
          ← All sets
        </button>
        <span className="spacer" />
        <label className="toggle">
          <input
            type="checkbox"
            checked={ownedOnly}
            onChange={(e) => setOwnedOnly(e.target.checked)}
          />
          Owned only
        </label>
        <label className="field grow">
          Find a card
          <input
            type="text"
            value={cardFilter}
            placeholder="name or number"
            onChange={(e) => setCardFilter(e.target.value)}
          />
        </label>
      </div>
      <h2>{active.set_name}</h2>
      <p className="sub">
        {visibleCards.length} of {cards.length} cards · tap to value · ✎ to track ownership
      </p>
      {loadingCards ? (
        <p className="empty">Loading…</p>
      ) : (
        <div className="cardgrid">
          {visibleCards.map((c) => {
            const entry = collection[c.id] ?? EMPTY;
            const query = `${c.name} ${c.number}`;
            return (
              <div key={c.id} className={`cardtile ${entry.owned > 0 ? "owned" : ""}`}>
                <button className="cardtap" title="Value this card" onClick={() => onPick(query)}>
                  {c.image_url ? (
                    <img src={c.image_url} alt="" loading="lazy" />
                  ) : (
                    <div className="noimg">{c.number}</div>
                  )}
                  <div className="cardname">{c.name}</div>
                  <div className="sub">
                    {c.number}
                    {c.rarity ? ` · ${c.rarity}` : ""}
                  </div>
                </button>
                <div className="ownbar">
                  <label className="ownqty" title="How many you own">
                    <input
                      type="number"
                      min="0"
                      value={entry.owned}
                      onChange={(e) => patchCard(c.id, { owned: Number(e.target.value) || 0 })}
                    />
                    owned
                  </label>
                  {entry.for_sale && <span className="forsale">FOR SALE</span>}
                  {entry.listings.length > 0 && (
                    <span className="listcount" title="Listings tracked">
                      🏷️ {entry.listings.length}
                    </span>
                  )}
                  <button
                    className="editbtn"
                    onClick={() => setOpenCard(openCard === c.id ? null : c.id)}
                  >
                    ✎
                  </button>
                </div>
                {openCard === c.id && (
                  <CardEditor
                    cardId={c.id}
                    entry={entry}
                    onPatch={(p) => patchCard(c.id, p)}
                    onChanged={(updated) =>
                      setCollection((prev) => ({ ...prev, [c.id]: updated }))
                    }
                  />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function CardEditor({
  cardId,
  entry,
  onPatch,
  onChanged,
}: {
  cardId: string;
  entry: CollectionEntry;
  onPatch: (p: Partial<Omit<CollectionEntry, "listings">>) => void;
  onChanged: (e: CollectionEntry & { card_id: string }) => void;
}) {
  const [listingUrl, setListingUrl] = useState("");

  const onAddListing = async () => {
    const url = listingUrl.trim();
    if (!url.startsWith("http")) return;
    const updated = await addCollectionListing(cardId, url);
    onChanged(updated);
    setListingUrl("");
  };

  return (
    <div className="editor">
      <div className="erow">
        <label className="field">
          Condition
          <input
            type="text"
            placeholder="NM · LP · PSA 9"
            defaultValue={entry.condition}
            onBlur={(e) => onPatch({ condition: e.target.value })}
          />
        </label>
        <label className="field">
          Paid £
          <input
            type="number"
            min="0"
            step="0.01"
            defaultValue={entry.paid ?? ""}
            onBlur={(e) => onPatch({ paid: e.target.value === "" ? null : Number(e.target.value) })}
          />
        </label>
        <label className="field">
          Target £
          <input
            type="number"
            min="0"
            step="0.01"
            defaultValue={entry.target_price ?? ""}
            onBlur={(e) =>
              onPatch({ target_price: e.target.value === "" ? null : Number(e.target.value) })
            }
          />
        </label>
        <label className="toggle">
          <input
            type="checkbox"
            checked={entry.for_sale}
            onChange={(e) => onPatch({ for_sale: e.target.checked })}
          />
          For sale
        </label>
      </div>
      <label className="field grow">
        Notes
        <input
          type="text"
          placeholder="anything worth remembering"
          defaultValue={entry.notes}
          onBlur={(e) => onPatch({ notes: e.target.value })}
        />
      </label>
      <div className="listings">
        <div className="lhead">My listings for this card</div>
        {entry.listings.length === 0 && <div className="sub">None yet.</div>}
        {entry.listings.map((l) => (
          <div key={l.url} className="lrow">
            <a href={l.url} target="_blank" rel="noreferrer">
              {l.source === "ebay" ? "eBay" : "link"}
              {l.price != null ? ` · £${l.price.toFixed(2)}` : ""} ↗
            </a>
            <button
              className="chipx"
              title="Remove listing"
              onClick={async () => onChanged(await removeCollectionListing(cardId, l.url))}
            >
              ×
            </button>
          </div>
        ))}
        <div className="erow">
          <input
            type="text"
            className="grow"
            placeholder="Paste an eBay listing URL…"
            value={listingUrl}
            onChange={(e) => setListingUrl(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") onAddListing();
            }}
          />
          <button className="linkbtn" onClick={onAddListing}>
            ➕ Add
          </button>
        </div>
      </div>
    </div>
  );
}
