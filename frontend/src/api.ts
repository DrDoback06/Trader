import type {
  Allocation,
  CatalogueCard,
  CollectionEntry,
  Deal,
  GemCard,
  Portfolio,
  RelistPreview,
  Rules,
  ScanResult,
  SealedPreset,
  SetInfo,
  SourcesResponse,
  SourceState,
} from "./types";

// Empty default = same-origin fetches. The backend serves the built dashboard from
// the same process, so /deals etc. resolve to whatever host:port the browser is on
// (works on localhost, a LAN IP, a tunnel URL, anywhere). Set VITE_API_BASE only
// during `npm run dev` when the frontend is on :5173 and the API on :8000.
const API_BASE = import.meta.env.VITE_API_BASE ?? "";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...init,
  });
  if (!res.ok) {
    let detail = `API error ${res.status}`;
    try {
      const body = await res.json();
      if (body && typeof body.detail === "string") {
        detail = body.detail;
      }
    } catch {
      // non-JSON error body; keep the default message
    }
    throw new Error(detail);
  }
  return (await res.json()) as T;
}

export function fetchDeals(
  onlyPassing: boolean,
  options: { mode?: string; withinHours?: number } = {},
): Promise<Deal[]> {
  const params = new URLSearchParams({ only_passing: String(onlyPassing) });
  if (options.mode && options.mode !== "all") params.set("mode", options.mode);
  if (options.withinHours != null) params.set("within_hours", String(options.withinHours));
  return request<Deal[]>(`/deals?${params.toString()}`);
}

export function fetchSources(): Promise<SourcesResponse> {
  return request<SourcesResponse>("/sources");
}

export function updateCredentials(
  values: Record<string, string>,
): Promise<SourcesResponse> {
  return request<SourcesResponse>("/sources/credentials", {
    method: "PUT",
    body: JSON.stringify(values),
  });
}

export function clearCredential(key: string): Promise<SourcesResponse> {
  return request<SourcesResponse>(`/sources/credentials/${key}`, { method: "DELETE" });
}

export function testEbayKeys(): Promise<{ ok: boolean; detail: string }> {
  return request("/sources/test/ebay", { method: "POST" });
}

export function testRapidApiKey(): Promise<{ ok: boolean; detail: string }> {
  return request("/sources/test/rapidapi", { method: "POST" });
}

export function setSourceEnabled(id: string, enabled: boolean): Promise<SourceState> {
  return request<SourceState>(`/sources/${id}`, {
    method: "PUT",
    body: JSON.stringify({ enabled }),
  });
}

export interface ScanOptions {
  mode: string;
  ending_within_hours?: number;
  max_price?: number;
  max_valuations?: number;
}

export function runScan(opts: ScanOptions): Promise<ScanResult> {
  return request<ScanResult>("/scan", { method: "POST", body: JSON.stringify(opts) });
}

export interface CardSearchInput {
  query: string;
  max_price?: number;
}

export function searchCardListings(input: CardSearchInput): Promise<ScanResult> {
  return request<ScanResult>("/scan/card", { method: "POST", body: JSON.stringify(input) });
}

export interface CardsScanOptions {
  graded?: boolean;
  include_misspellings?: boolean;
  max_price?: number;
  max_valuations?: number;
}

// Run the saved card list as a batch of per-card live searches (the scan button).
export function scanCards(opts: CardsScanOptions = {}): Promise<ScanResult> {
  return request<ScanResult>("/scan/cards", { method: "POST", body: JSON.stringify(opts) });
}

export function fetchCards(): Promise<{ cards: string[] }> {
  return request<{ cards: string[] }>("/cards");
}

export function addCard(query: string): Promise<{ cards: string[] }> {
  return request<{ cards: string[] }>("/cards", {
    method: "POST",
    body: JSON.stringify({ query }),
  });
}

export function removeCard(query: string): Promise<{ cards: string[] }> {
  return request<{ cards: string[] }>(`/cards?query=${encodeURIComponent(query)}`, {
    method: "DELETE",
  });
}

export interface EvaluateInput {
  query: string;
  ask_price: number;
  shipping?: number;
}

export function evaluateCard(input: EvaluateInput): Promise<Deal> {
  return request<Deal>("/evaluate", { method: "POST", body: JSON.stringify(input) });
}

export function fetchRules(): Promise<{ rules: Rules }> {
  return request("/settings");
}

export function updateRules(patch: Record<string, number>): Promise<{ rules: Rules }> {
  return request("/settings", { method: "PUT", body: JSON.stringify(patch) });
}

export interface AlertStatus {
  interval_min: number;
  channel: string;
  running: boolean;
}

export function fetchAlertStatus(): Promise<AlertStatus> {
  return request<AlertStatus>("/alerts/status");
}

export function setSchedule(interval_min: number): Promise<AlertStatus> {
  return request<AlertStatus>("/alerts/schedule", {
    method: "POST",
    body: JSON.stringify({ interval_min }),
  });
}

export function testAlert(): Promise<{ sent: boolean; channel: string }> {
  return request("/alerts/test", { method: "POST", body: JSON.stringify({}) });
}

export function fetchSets(): Promise<{ total_cards: number; sets: SetInfo[] }> {
  return request("/catalogue/sets");
}

export function fetchSetCards(
  setCode: string,
): Promise<{ set_code: string; set_name: string; cards: CatalogueCard[] }> {
  return request(`/catalogue/sets/${encodeURIComponent(setCode)}/cards`);
}

export function fetchAllocation(budget?: number): Promise<Allocation> {
  return request<Allocation>(`/allocate${budget != null ? `?budget=${budget}` : ""}`);
}

export function fetchPortfolio(): Promise<Portfolio> {
  return request<Portfolio>("/portfolio");
}

export function buyDeal(dealId: string): Promise<{ position_id: number }> {
  return request("/portfolio/buy", { method: "POST", body: JSON.stringify({ deal_id: dealId }) });
}

export function sellPosition(id: number, price: number): Promise<Portfolio> {
  return request<Portfolio>(`/portfolio/${id}/sell`, {
    method: "POST",
    body: JSON.stringify({ price }),
  });
}

export function relistPreview(id: number): Promise<RelistPreview> {
  return request<RelistPreview>(`/portfolio/${id}/relist`, {
    method: "POST",
    body: JSON.stringify({ publish: false }),
  });
}

// --- collection (owned cards + listings) ---

export function fetchCollection(): Promise<{ cards: Record<string, CollectionEntry> }> {
  return request("/collection");
}

// Card ids contain '/', so the id travels in the body/query, not the URL path.
export function updateCollectionCard(
  cardId: string,
  patch: Partial<Omit<CollectionEntry, "listings">>,
): Promise<CollectionEntry & { card_id: string }> {
  return request("/collection/card", {
    method: "PUT",
    body: JSON.stringify({ card_id: cardId, ...patch }),
  });
}

export function addCollectionListing(
  cardId: string,
  url: string,
): Promise<CollectionEntry & { card_id: string }> {
  return request("/collection/listings", {
    method: "POST",
    body: JSON.stringify({ card_id: cardId, url }),
  });
}

export function removeCollectionListing(
  cardId: string,
  ref: string,
): Promise<CollectionEntry & { card_id: string }> {
  const qs = `card_id=${encodeURIComponent(cardId)}&ref=${encodeURIComponent(ref)}`;
  return request(`/collection/listings?${qs}`, { method: "DELETE" });
}

export function importEbayListings(): Promise<{
  found: number;
  matched: number;
  unmatched: string[];
  note: string;
}> {
  return request("/collection/import/ebay", { method: "POST" });
}

export function fetchSealed(): Promise<{ sealed: SealedPreset[] }> {
  return request("/catalogue/sealed");
}

// --- hidden gems ---

export interface GemsOptions {
  limit?: number;
  set_code?: string;
  min_value?: number;
}

export function fetchGems(opts: GemsOptions = {}): Promise<{ gems: GemCard[]; threshold: number }> {
  const params = new URLSearchParams();
  if (opts.limit != null) params.set("limit", String(opts.limit));
  if (opts.set_code) params.set("set_code", opts.set_code);
  if (opts.min_value != null) params.set("min_value", String(opts.min_value));
  const qs = params.toString();
  return request(`/gems${qs ? `?${qs}` : ""}`);
}
