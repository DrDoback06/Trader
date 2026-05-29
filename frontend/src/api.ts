import type {
  Allocation,
  CatalogueCard,
  Deal,
  Portfolio,
  RelistPreview,
  ScanResult,
  SetInfo,
  SourcesResponse,
  SourceState,
} from "./types";

const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8000";

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

export function fetchDeals(onlyPassing: boolean): Promise<Deal[]> {
  return request<Deal[]>(`/deals?only_passing=${onlyPassing}`);
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
}

export function runScan(opts: ScanOptions): Promise<ScanResult> {
  return request<ScanResult>("/scan", { method: "POST", body: JSON.stringify(opts) });
}

export interface EvaluateInput {
  query: string;
  ask_price: number;
  shipping?: number;
}

export function evaluateCard(input: EvaluateInput): Promise<Deal> {
  return request<Deal>("/evaluate", { method: "POST", body: JSON.stringify(input) });
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
