import { useState } from "react";
import { BrowsePage } from "./components/BrowsePage";
import { DealsPage } from "./components/DealsPage";
import { PortfolioPage } from "./components/PortfolioPage";
import { SourcesPage } from "./components/SourcesPage";

type View = "deals" | "browse" | "portfolio" | "sources";

export default function App() {
  const [view, setView] = useState<View>("deals");
  const [checkPrefill, setCheckPrefill] = useState<string | null>(null);

  const pickCard = (query: string) => {
    setCheckPrefill(query);
    setView("deals");
  };

  return (
    <div className="app">
      <header className="topbar">
        <div>
          <h1>Trader</h1>
          <p className="tagline">
            UK TCG deal finder — find underpriced cards, buy manually, flip for profit.
          </p>
        </div>
        <nav className="nav">
          <button className={view === "deals" ? "active" : ""} onClick={() => setView("deals")}>
            Deals
          </button>
          <button className={view === "browse" ? "active" : ""} onClick={() => setView("browse")}>
            Browse
          </button>
          <button
            className={view === "portfolio" ? "active" : ""}
            onClick={() => setView("portfolio")}
          >
            Portfolio
          </button>
          <button className={view === "sources" ? "active" : ""} onClick={() => setView("sources")}>
            Sources &amp; Keys
          </button>
        </nav>
      </header>

      {view === "deals" && (
        <DealsPage prefillQuery={checkPrefill} onPrefillConsumed={() => setCheckPrefill(null)} />
      )}
      {view === "browse" && <BrowsePage onPick={pickCard} />}
      {view === "portfolio" && <PortfolioPage />}
      {view === "sources" && <SourcesPage />}

      <footer className="foot">
        Decision-support only — no automated buying. You are responsible for your own purchases and
        any UK tax obligations. Estimated values and fees are configurable approximations.
      </footer>
    </div>
  );
}
