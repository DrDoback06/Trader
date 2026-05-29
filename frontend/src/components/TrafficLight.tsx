import type { ReactNode } from "react";

/** A coloured pill: GREEN / AMBER / RED, for fast visual triage. */
export function TrafficLight({
  tier,
  children,
  title,
}: {
  tier: string;
  children: ReactNode;
  title?: string;
}) {
  return (
    <span className={`tl tl-${tier}`} title={title}>
      {children}
    </span>
  );
}
