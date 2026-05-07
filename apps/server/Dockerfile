FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY phonos_server/ phonos_server/

EXPOSE 8765

ENV PHONOS_PORT=8765

CMD ["sh", "-c", "exec uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port ${PHONOS_PORT}"]
