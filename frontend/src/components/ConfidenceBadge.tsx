export function ConfidenceBadge({ value }: { value: number }) {
  const pct = Math.round(value * 100);
  let level = "low";
  if (value >= 0.75) {
    level = "high";
  } else if (value >= 0.55) {
    level = "mid";
  }
  return <span className={`conf conf-${level}`}>{pct}%</span>;
}
