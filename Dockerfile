# syntax=docker/dockerfile:1

# ---- Stage 1: build the React dashboard ----
FROM node:20-slim AS frontend
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ---- Stage 2: Python runtime serving the API + the built dashboard ----
FROM python:3.11-slim AS app
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY pyproject.toml ./
COPY backend/ ./backend/
RUN pip install -e .

# The compiled dashboard (main.py serves it when present).
COPY --from=frontend /app/frontend/dist ./frontend/dist

# Best-effort: bake the full Pokémon catalogue into the image. The deploy host can
# reach pokemontcg.io (unlike the dev sandbox); if it can't, we fall back to seeds.
RUN python -m trader.tools.import_pokemontcg || echo "catalogue import skipped; using seed sets"

EXPOSE 8000
# Hosts (Render/Railway/Fly) inject $PORT.
CMD ["sh", "-c", "uvicorn trader.main:app --app-dir backend --host 0.0.0.0 --port ${PORT:-8000}"]
