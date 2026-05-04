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
- [ ] Write `packages/protocol/openapi.yaml` — shared API specification
- [ ] Create `apps/server/` skeleton:
  - `pyproject.toml` with dependencies
  - `Dockerfile`
  - `docker-compose.yml`
  - `.env.example`
  - `README.md`
- [ ] Create `apps/macos/` skeleton:
  - Xcode project or `Package.swift`
  - `README.md`

**Commit**: `feat: bootstrap monorepo structure and documentation`

---

## Phase 2: Server MVP — Transcription Engine

**Goal**: Working server that accepts audio and returns transcripts.

### 2.1 Core Server

- [ ] FastAPI application with uvicorn
- [ ] Configuration via environment variables
- [ ] `GET /health` — returns model status and uptime
- [ ] `GET /models` — lists configured model names
- [ ] `GET /models/active` — returns currently loaded model
- [ ] `PUT /models/active` — switches active model with lock safety
- [ ] `POST /transcribe` — accepts multipart audio, returns transcription
- [ ] Optional token-based authentication (`PHONOS_AUTH_TOKEN`)

**Details**:
- Use `faster-whisper` for transcription
- Default model: `base.en`
- CPU compute: `int8`
- VAD filter enabled by default
- Model switch must be safe during transcription (use threading.Lock)
- Transcription returns: `{text, model, language, duration_seconds, processing_seconds}`

### 2.2 Docker Deployment

- [ ] `Dockerfile` — Python 3.11 slim, server dependencies
- [ ] `docker-compose.yml` — single service, env vars, port mapping
- [ ] `.env.example` — all config vars with comments
- [ ] Model cache volume mount for persistence
- [ ] Health check in compose

### 2.3 Tests

- [ ] Test `/health` endpoint
- [ ] Test `/models` and `/models/active` endpoints
- [ ] Test `/transcribe` with known audio sample
- [ ] Test model switching
- [ ] Test auth token rejection

**Commit**: `feat(server): implement transcription API with faster-whisper`

---

## Phase 3: Mac Client MVP — Menu Bar & Settings

**Goal**: Functional macOS menu-bar app with server connectivity.

### 3.1 App Shell

- [ ] SwiftUI/AppKit menu-bar app
- [ ] Status item in menu bar with icon
- [ ] Menu with app actions
- [ ] Settings window/popover:
  - Server URL
  - Auth token
  - Hotkey preference
- [ ] Connection status indicator

### 3.2 Server Integration

- [ ] Health check on app launch and settings change
- [ ] Fetch model list from server
- [ ] Model selector in settings
- [ ] Set active model on server
- [ ] Display server status (online/offline/error)

**Commit**: `feat(macos): menu-bar app shell with server settings`

---

## Phase 4: Audio Recording & Transcription

**Goal**: Capture microphone audio, send to server, receive and display transcript.

### 4.1 Audio Capture

- [ ] Request microphone permission
- [ ] Configure `AVAudioEngine` for microphone input
- [ ] Record audio to temp WAV file
- [ ] Recording indicator (status item change, audio level)

### 4.2 Transcription Upload

- [ ] Upload recorded audio to `POST /transcribe`
- [ ] Handle server errors (offline, auth failure, model loading)
- [ ] Display transcript in menu UI
- [ ] Show transcription metadata (duration, processing time, model)

**Commit**: `feat(macos): audio recording and transcription upload`

---

## Phase 5: Global Hotkey

**Goal**: Hands-free dictation trigger.

### 5.1 Hotkey Implementation

- [ ] Request Accessibility permission
- [ ] Implement low-level keyboard event tap
- [ ] Attempt `Fn`/`Globe` key detection
- [ ] Fall back to left `Control` key
- [ ] Configurable backup shortcut in settings

### 5.2 Recording Modes

- [ ] Hold-to-record: key-down starts, key-up stops and transcribes
- [ ] Toggle recording: key press toggles recording on/off
- [ ] Mode selection in settings
- [ ] Visual feedback for recording state

**Commit**: `feat(macos): global hotkey with hold/toggle recording`

---

## Phase 6: Direct Paste

**Goal**: Transcript appears in the active application.

- [ ] Accessibility permission for paste automation
- [ ] Copy transcript to clipboard
- [ ] Simulate `Cmd+V` in frontmost application
- [ ] Attempt clipboard restoration after paste
- [ ] Fallback: clipboard-only mode if accessibility not granted

**Commit**: `feat(macos): direct paste transcript into active app`

---

## Phase 7: Model Switching from Client

**Goal**: Change Whisper models from the Mac app.

- [ ] List server models in settings UI
- [ ] Select model from dropdown/picker
- [ ] Send `PUT /models/active` to server
- [ ] Show model change confirmation and new model info
- [ ] Handle model loading errors gracefully

**Commit**: `feat(macos): model selection from client`

---

## Phase 8: Deployment & Hardening

**Goal**: Production-ready deployment documentation and error handling.

- [ ] Write `docs/deployment.md` — Tailscale + Docker setup guide
- [ ] Tailscale MagicDNS configuration
- [ ] Firewall recommendations
- [ ] Token auth setup guide
- [ ] Model recommendations for CPU (speed vs accuracy table)
- [ ] Better error states in Mac app (offline, loading, errors)
- [ ] Logging and observability
- [ ] Server startup script / systemd service example

**Commit**: `docs: deployment guide and hardening`

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
