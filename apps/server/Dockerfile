FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
COPY phonos_server/ phonos_server/

RUN pip install --no-cache-dir .

EXPOSE 8765

CMD ["uvicorn", "phonos_server.main:app", "--host", "0.0.0.0", "--port", "8765"]
