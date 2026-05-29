import { useState } from "react";
import { DealsPage } from "./components/DealsPage";
import { SourcesPage } from "./components/SourcesPage";

type View = "deals" | "sources";

export default function App() {
  const [view, setView] = useState<View>("deals");

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
          <button className={view === "sources" ? "active" : ""} onClick={() => setView("sources")}>
            Sources &amp; Keys
          </button>
        </nav>
      </header>

      {view === "deals" ? <DealsPage /> : <SourcesPage />}

      <footer className="foot">
        Decision-support only — no automated buying. You are responsible for your own purchases and
        any UK tax obligations. Estimated values and fees are configurable approximations.
      </footer>
    </div>
  );
}
