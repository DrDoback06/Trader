# Trader — frontend

Vite + React + TypeScript dashboard that renders the ranked deals from the backend API.

## Run

```bash
npm install
npm run dev        # http://localhost:5173  (expects the backend on :8000)
```

Point it at a different backend with `VITE_API_BASE`:

```bash
VITE_API_BASE=http://localhost:8000 npm run dev
```

## Build / check

```bash
npm run build      # type-check (tsc --noEmit) + production bundle
npm run typecheck
```

The Phase 1 dashboard shows ranked **demo** deals (the backend serves them from bundled
sample data — no API keys needed). Later phases add watchlist, settings, and portfolio views.
