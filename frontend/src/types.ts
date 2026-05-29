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
  sales_per_week: number | null;
  days_to_sell: number | null;
  provider: string;
}

export interface Listing {
  title: string;
  price: Money;
  shipping: Money | null;
  buying_format: string;
  item_end_date: string | null;
  accepts_best_offer: boolean;
  bid_count: number | null;
  current_bid_price: Money | null;
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

export interface Allocation {
  budget: { amount: number; display: string };
  total_cost: { amount: number; display: string };
  total_expected_profit: number;
  skipped_over_budget: number;
  chosen: Deal[];
}

export interface Position {
  id: number;
  card: string;
  cost_basis: number;
  est_value: number;
  status: string;
  sold_price: number | null;
  url: string;
}

export interface Portfolio {
  positions: Position[];
  held: number;
  invested: number;
  unrealised_pnl: number;
  realised_pnl: number;
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

export interface Grading {
  graded_value: Money;
  expected_profit: Money;
  expected_roi: number;
  gem_rate: number;
  worth_grading: boolean;
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
  hold_candidate: boolean;
  annualised_roi: number | null;
  max_bid: Money | null;
  grading: Grading | null;
  trend_pct: number | null;
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
