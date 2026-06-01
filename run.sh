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
# Import the app the SAME way it launches below (backend on the path), so a flaky
# editable install never makes a working app look "broken".
export PYTHONPATH="$PWD/backend${PYTHONPATH:+:$PYTHONPATH}"

echo "→ [1/3] Python environment"
if [ ! -d .venv ]; then
  "$PY" -m venv .venv
fi
# Skip the (network) install if the app + key libraries already import.
if .venv/bin/python -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn" 2>/dev/null; then
  echo "  packages already installed - skipping download"
else
  .venv/bin/pip install -q --timeout 120 --retries 10 --upgrade pip
  .venv/bin/pip install -q --timeout 120 --retries 10 -e ".[dev]"
  # A dropped download can leave a compiled package (e.g. pydantic-core) half-installed
  # while pip still reports it satisfied. If the app won't import, re-fetch the compiled
  # core packages fresh (no cache) before surfacing the real error.
  if ! .venv/bin/python -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn" 2>/dev/null; then
    echo "  a package looks half-installed - repairing (fresh download)…"
    .venv/bin/pip install --force-reinstall --no-cache-dir --timeout 120 --retries 10 \
      pydantic pydantic-core greenlet rapidfuzz
  fi
  # Surface the real error (not a misleading "network" message) if it STILL won't import.
  .venv/bin/python -c "import trader, sqlalchemy, apscheduler, fastapi, uvicorn"
fi

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
