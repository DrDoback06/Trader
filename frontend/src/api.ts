import type { Deal } from "./types";

const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8000";

export async function fetchDeals(onlyPassing: boolean): Promise<Deal[]> {
  const res = await fetch(`${API_BASE}/deals?only_passing=${onlyPassing}`);
  if (!res.ok) {
    throw new Error(`API error ${res.status}`);
  }
  return (await res.json()) as Deal[];
}
