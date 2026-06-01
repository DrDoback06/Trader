import { useEffect, useState } from "react";
import { fetchSources } from "../api";
import type { SourceState } from "../types";

function isActive(sources: SourceState[], id: string): boolean {
  return sources.some((s) => s.id === id && s.active);
}

export function ValuationStatusBanner() {
  const [sources, setSources] = useState<SourceState[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchSources()
      .then((r) => {
        if (!cancelled) setSources(r.sources);
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : "load failed");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (error || !sources) return null;

  const ebaySold = isActive(sources, "ebay_uk_sold");
  const pokemontcg = isActive(sources, "pokemontcg_market");
  const vision = isActive(sources, "vision_estimate");
  const ebayActive = isActive(sources, "ebay_uk_active");

  const noValuation = !ebaySold && !pokemontcg && !vision;
  const onlyFree = !ebaySold && pokemontcg;

  if (noValuation) {
    return (
      <div className="banner banner-bad">
        🔴 <strong>No valuation source connected</strong> — every ROI will be blank. Turn one on
        under <strong>Sources &amp; Keys</strong>: the free pokemontcg.io market price needs no key
        and works for raw cards.
      </div>
    );
  }

  if (!ebayActive) {
    return (
      <div className="banner banner-warn">
        ⚠️ <strong>No live eBay scanner connected</strong> — you can see ROIs on bundled samples,
        but to scan real listings you need eBay App ID + Cert ID under <strong>Sources &amp; Keys</strong>.
        {onlyFree && (
          <>
            {" "}
            Graded slabs will read <code>—</code> until you add a RapidAPI key (or turn on the
            Claude rough-estimate fallback).
          </>
        )}
      </div>
    );
  }

  if (onlyFree) {
    return (
      <div className="banner banner-warn">
        ⚠️ Using <strong>free pokemontcg.io fallback</strong> only — raw-card ROIs will populate,
        but graded slabs (PSA/CGC) need real sold comps. Add a <strong>RapidAPI key</strong> (or
        turn on the <strong>Claude rough-estimate</strong> fallback) under Sources &amp; Keys.
      </div>
    );
  }

  if (vision && !ebaySold) {
    return (
      <div className="banner banner-warn">
        ⚠️ Live eBay sold prices are off — Claude rough estimates are filling the gap. Rows marked{" "}
        <code>est. (rough)</code> are AI guesses, not real comps. Add a RapidAPI key for proper UK
        sold prices.
      </div>
    );
  }

  return (
    <div className="banner banner-good">
      💚 <strong>Live eBay UK sold prices</strong> on — ROIs reflect real comps.
      {pokemontcg && <> Free fallback (pokemontcg.io) is also on, so a value lands even on rate-limit.</>}
    </div>
  );
}
