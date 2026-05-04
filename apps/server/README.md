# Phonos Server

Local Whisper transcription server for the Phonos dictation system.

## Quick Start

```bash
# Copy environment config
cp .env.example .env
# Optional: edit .env to set PHONOS_AUTH_TOKEN

# Build and start
docker compose up -d

# Check health
curl http://localhost:8765/health
```

## Endpoints

| Method | Path              | Purpose                            |
|--------|-------------------|------------------------------------|
| GET    | `/health`         | Server health + model info         |
| GET    | `/models`         | List configured models             |
| GET    | `/models/active`  | Get currently loaded model         |
| PUT    | `/models/active`  | Switch active model                |
| POST   | `/transcribe`     | Transcribe uploaded audio file     |

## Config

See `.env.example` for all environment variables.

Docker Compose binds to `127.0.0.1` by default. If another machine needs to reach the server, set `PHONOS_BIND=0.0.0.0` and configure `PHONOS_AUTH_TOKEN`.

Default transcription models are `tiny.en`, `base.en`, `small.en`, `medium.en`, `large-v3`, `turbo`, and `distil-large-v3`. Larger models are more accurate but slower and require more memory; `turbo` and `distil-large-v3` are good candidates to try when you want better quality than `base.en` without the full `large-v3` cost.

## Run Without Docker

```bash
uv sync
uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

To run tests:
```bash
uv run pytest
```
