# Deploying Trader (get a URL you can open on your phone)

The app is **one service**: a Python (FastAPI) backend that also serves the React
dashboard. So it needs a host that runs Python — a static-only host (Netlify/Vercel)
can host the dashboard but **not** the backend.

## Option A — Render (recommended, free, phone-friendly) ✅

One HTTPS URL, backend + dashboard together, deploys straight from GitHub.

1. On your phone, go to **render.com** and sign up (GitHub login is easiest).
2. **New → Blueprint**.
3. Connect the **`drdoback06/trader`** repo and select branch
   **`claude/vibrant-faraday-HuOEu`**. Render reads [`render.yaml`](../render.yaml).
4. **Apply**. First build takes ~3–6 min (it builds the dashboard, installs Python,
   and imports the full card catalogue).
5. Open the `…onrender.com` URL → **Sources & Keys** → paste your eBay + RapidAPI
   keys (or set them as env vars in Render first) → **Deals → Run live eBay scan**.

> Free Render services sleep after ~15 min idle, so the first hit after a nap takes
> ~30s to wake. Fine for testing.

## Option B — Railway / Fly.io (also fine)

Both auto-detect the [`Dockerfile`](../Dockerfile):
- **Railway:** New Project → Deploy from GitHub repo → it builds the Dockerfile → exposes a URL.
- **Fly.io:** `fly launch` (uses the Dockerfile), `fly deploy`.

## Option C — Netlify (dashboard only, backend elsewhere)

Netlify can host the **dashboard**, but you still need the backend on Render/Railway/Fly.
- Backend: deploy via Option A/B, note its `https://…` URL.
- Netlify: New site from Git → base `frontend`, build `npm run build`, publish `dist`,
  and set env var `VITE_API_BASE=https://your-backend-url`.

This is more moving parts than Option A — only pick it if you specifically want Netlify.

## Keys

Set as environment variables on the host (persist across redeploys) **or** type them
into the in-app **Sources & Keys** page (stored on the server, masked when read):
`EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_ENV` (`sandbox`|`production`),
`RAPIDAPI_KEY`, optional `POKEMONTCG_API_KEY`.

## ⚠️ Security

A public URL means anyone who finds it can use the app and spend your eBay/RapidAPI
quota. **Set `ACCESS_PASSWORD`** (an env var) to gate the whole app behind an HTTP
Basic prompt — your browser asks once, then remembers it. `/health` stays open so
Render's health check still works. With no `ACCESS_PASSWORD` set, the app is open.
