# Phonos Roadmap

## Phase 1: Monorepo Bootstrap

**Goal**: Repository structure, documentation, and development environment.

- [x] Initialize git repository
- [x] Create monorepo directory structure
  - `apps/server/`
  - `apps/macos/`
  - `packages/protocol/`
  - `docs/`
- [x] Write `README.md` with project overview
- [x] Write `docs/architecture.md` with component design
- [x] Write `docs/roadmap.md` (this file)
- [x] Write `packages/protocol/openapi.yaml` — shared API specification
- [x] Create `apps/server/` skeleton:
  - `pyproject.toml` with dependencies
  - `Dockerfile`
  - `docker-compose.yml`
  - `.env.example`
  - `README.md`
- [x] Create `apps/macos/` skeleton:
  - Xcode project or `Package.swift`
  - `README.md`

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 2: Server MVP — Transcription Engine

**Goal**: Working server that accepts audio and returns transcripts.

### 2.1 Core Server

- [x] FastAPI application with uvicorn
- [x] Configuration via environment variables
- [x] `GET /health` — returns model status and uptime
- [x] `GET /models` — lists configured model names
- [x] `GET /models/active` — returns currently loaded model
- [x] `PUT /models/active` — switches active model with lock safety
- [x] `POST /transcribe` — accepts multipart audio, returns transcription
- [x] Optional token-based authentication (`PHONOS_AUTH_TOKEN`)

**Details**:
- Use `faster-whisper` for transcription
- Default model: `base.en`
- CPU compute: `int8`
- VAD filter enabled by default
- Model switch must be safe during transcription (use threading.Lock)
- Transcription returns: `{text, model, language, duration_seconds, processing_seconds}`

### 2.2 Docker Deployment

- [x] `Dockerfile` — Python 3.11 slim, server dependencies
- [x] `docker-compose.yml` — single service, env vars, port mapping
- [x] `.env.example` — all config vars with comments
- [x] Model cache volume mount for persistence
- [x] Health check in compose

### 2.3 Tests

- [x] Test `/health` endpoint
- [x] Test `/models` and `/models/active` endpoints
- [x] Test `/transcribe` with known audio sample
- [x] Test model switching
- [x] Test auth token rejection

**Commit**: `79b98a8` — `test(server): add API tests for health, models, transcribe, auth`

---

## Phase 3: Mac Client MVP — Menu Bar & Settings

**Goal**: Functional macOS menu-bar app with server connectivity.

### 3.1 App Shell

- [x] SwiftUI/AppKit menu-bar app
- [x] Status item in menu bar with icon
- [x] Menu with app actions
- [x] Settings window/popover:
  - Server URL
  - Auth token
  - Hotkey preference
- [x] Connection status indicator

### 3.2 Server Integration

- [x] Health check on app launch and settings change
- [x] Fetch model list from server
- [x] Model selector in settings
- [x] Set active model on server
- [x] Display server status (online/offline/error)

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 4: Audio Recording & Transcription

**Goal**: Capture microphone audio, send to server, receive and display transcript.

### 4.1 Audio Capture

- [x] Request microphone permission
- [x] Configure `AVAudioEngine` for microphone input
- [x] Record audio to temp WAV file
- [x] Recording indicator (status item change, audio level)

### 4.2 Transcription Upload

- [x] Upload recorded audio to `POST /transcribe`
- [x] Handle server errors (offline, auth failure, model loading)
- [x] Display transcript in menu UI
- [x] Show transcription metadata (duration, processing time, model)

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 5: Global Hotkey

**Goal**: Hands-free dictation trigger.

### 5.1 Hotkey Implementation

- [x] Request Accessibility permission
- [x] Implement low-level keyboard event tap
- [ ] Attempt `Fn`/`Globe` key detection (needs runtime testing)
- [x] Fall back to left `Control` key
- [x] Configurable backup shortcut in settings

### 5.2 Recording Modes

- [x] Hold-to-record: key-down starts, key-up stops and transcribes
- [x] Toggle recording: key press toggles recording on/off
- [x] Mode selection in settings
- [x] Visual feedback for recording state

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 6: Direct Paste

**Goal**: Transcript appears in the active application.

- [x] Accessibility permission for paste automation
- [x] Copy transcript to clipboard
- [x] Simulate `Cmd+V` in frontmost application
- [x] Attempt clipboard restoration after paste
- [x] Fallback: clipboard-only mode if accessibility not granted

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 7: Model Switching from Client

**Goal**: Change Whisper models from the Mac app.

- [x] List server models in settings UI
- [x] Select model from dropdown/picker
- [x] Send `PUT /models/active` to server
- [x] Show model change confirmation and new model info
- [x] Handle model loading errors gracefully

**Commit**: `93f3e40` — `feat: bootstrap phonos monorepo with server and mac client`

---

## Phase 8: Deployment & Hardening

**Goal**: Production-ready deployment documentation and error handling.

- [x] Write `docs/deployment.md` — Tailscale + Docker setup guide
- [x] Tailscale MagicDNS configuration
- [x] Firewall recommendations
- [x] Token auth setup guide
- [x] Model recommendations for CPU (speed vs accuracy table)
- [x] Better error states in Mac app (offline, loading, errors)
- [x] Logging and observability
- [x] Server startup script / systemd service example

**Commit**: `0881d69` — `docs: add deployment guide for Tailscale/Docker/local network`

---

## Phase 9: Future — Streaming Mode (Planned)

**Goal**: Lower latency with real-time partial transcripts.

- [ ] Add WebSocket endpoint to server for streaming transcription
- [ ] Implement VAD-based chunking on server
- [ ] Stream audio chunks from Mac client
- [ ] Live transcript preview in menu-bar popover
- [ ] Final transcript paste on completion
- [ ] Latency comparison: upload vs streaming

---

## Configuration Reference

### Server Environment Variables

```env
PHONOS_HOST=0.0.0.0          # Bind address
PHONOS_PORT=8765             # Server port
PHONOS_AUTH_TOKEN=           # Optional: Bearer token for API auth
PHONOS_MODEL=base.en         # Default model on startup
PHONOS_MODELS=...            # Comma-separated available models
PHONOS_DEVICE=cpu            # Device: cpu or cuda
PHONOS_COMPUTE_TYPE=int8     # Compute type for faster-whisper
PHONOS_VAD_FILTER=true       # Enable voice activity detection
```

### Mac Client Settings

| Setting        | Default                          | Description                      |
|---------------|----------------------------------|----------------------------------|
| Server URL     | `http://localhost:8765`          | Server address                   |
| Auth Token     | `""` (empty)                     | Bearer token for server auth     |
| Hotkey         | `Fn/Globe` → `Left Control`      | Recording trigger key            |
| Mode           | `hold`                           | `hold` or `toggle`               |
| Model          | `base.en`                        | Selected from server model list  |
