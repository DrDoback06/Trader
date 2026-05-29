export interface Money {
  amount: number;
  currency: string;
  display: string;
}

export interface CardRef {
  id: string;
  name: string;
  set_code: string;
  set_name: string;
  number: string;
  rarity: string | null;
}

export interface Economics {
  buy_cost: Money;
  est_value: Money;
  selling_fees: Money;
  net_proceeds: Money;
  profit: Money;
  roi: number;
  margin: number;
}

export interface Valuation {
  median: Money;
  low: Money | null;
  high: Money | null;
  sample_size: number;
  spread: number;
  provider: string;
}

export interface Listing {
  title: string;
  price: Money;
  shipping: Money | null;
  buying_format: string;
  item_end_date: string | null;
  url: string | null;
  image_url: string | null;
}

export interface SourceState {
  id: string;
  name: string;
  role: string;
  region: string;
  currency: string;
  requires: string[];
  signup_url: string;
  accuracy: string;
  available: boolean;
  configured: boolean;
  enabled: boolean;
  active: boolean;
}

export interface SourcesResponse {
  sources: SourceState[];
  credentials: Record<string, string | null>;
  note: string;
}

export interface ScanResult {
  mode: string;
  targets_scanned: number;
  calls_used: number;
  listings_seen: number;
  new_listings: number;
  quota_exhausted: boolean;
  deals: Deal[];
}

export interface Deal {
  id: string;
  source: string;
  passed_rules: boolean;
  score: number;
  confidence: number;
  sell_probability: number;
  sell_tier: string;
  profit_tier: string;
  discount: number | null;
  decision: string;
  match_score: number;
  card: CardRef | null;
  is_graded: boolean;
  grade: string | null;
  condition: string;
  language: string;
  flags: string[];
  listing: Listing;
  valuation: Valuation | null;
  economics: Economics | null;
  rule_reasons: string[];
}
