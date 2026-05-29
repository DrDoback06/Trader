#!/usr/bin/env bash
#
# One-command local runner for Trader.
#   ./run.sh            build + serve on http://localhost:8000
#   ./run.sh --catalogue  also import the full Pokémon catalogue first (needs network)
#
# Re-run any time; it's idempotent (only installs/builds what's missing or changed).
set -euo pipefail
cd "$(dirname "$0")"

PY="${PYTHON:-python3}"

echo "→ [1/3] Python environment"
if [ ! -d .venv ]; then
  "$PY" -m venv .venv
fi
.venv/bin/pip install -q --timeout 120 --retries 10 --upgrade pip
.venv/bin/pip install -q --timeout 120 --retries 10 -e ".[dev]"

if [ "${1:-}" = "--catalogue" ]; then
  echo "→ importing full Pokémon catalogue (pokemontcg.io must be reachable)"
  .venv/bin/python -m trader.tools.import_pokemontcg || \
    echo "  (catalogue import skipped/failed — the app still runs on bundled sample sets)"
fi

echo "→ [2/3] Dashboard build"
if [ ! -d frontend/node_modules ]; then
  npm --prefix frontend install
fi
npm --prefix frontend run build

echo "→ [3/3] Serving — open http://localhost:8000"
echo "   (paste your API keys under 'Sources & Keys'; each has a 'Where to get this ↗' link)"
exec .venv/bin/uvicorn trader.main:app --app-dir backend --host 0.0.0.0 --port "${PORT:-8000}"
