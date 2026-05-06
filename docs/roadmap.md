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
- [x] `GET /health` — returns model status and runtime config
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
- [x] Recording indicator (status item change)

### 4.2 Transcription Upload

- [x] Upload recorded audio to `POST /transcribe`
- [x] Handle server errors (offline, auth failure, model loading)
- [x] Display recent transcripts in menu/history UI
- [ ] Show transcription metadata (duration, processing time, model)

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
- [ ] Attempt clipboard restoration after paste
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
PHONOS_AUTH_TOKEN=           # Optional: Bearer token for API auth
PHONOS_MODEL=base.en         # Default model on startup
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3  # Available models
PHONOS_DEVICE=cpu            # Device: cpu or cuda
PHONOS_COMPUTE_TYPE=int8     # Compute type for faster-whisper
PHONOS_VAD_FILTER=true       # Enable voice activity detection
PHONOS_TRANSCRIBE_TIMEOUT_SECONDS=600  # Per-request transcription timeout
PHONOS_MAX_UPLOAD_MB=100     # Maximum uploaded audio file size
```

### Mac Client Settings

| Setting        | Default                          | Description                      |
|---------------|----------------------------------|----------------------------------|
| Server URL     | `http://localhost:8765`          | Server address                   |
| Auth Token     | `""` (empty)                     | Bearer token for server auth     |
| Hotkey         | `Control-Space`                  | Recording trigger shortcut       |
| Mode           | `hold`                           | `hold` or `toggle`               |
| Model          | `base.en`                        | Selected from server model list  |

---

## Post-1.0 To Do

This backlog comes from the first release code and feature review. Items are grouped by priority and include concrete acceptance criteria so they can be turned into focused implementation tasks.

### P0 — Reliability and Data Safety

#### Harden model loading state

- [x] Make `ModelManager.load()` transactional: do not publish the new active model until the worker has successfully loaded.
- [x] If worker startup fails, times out, or exits early, set the model status to `error` and clear or restore the active model consistently.
- [x] Add explicit status fields for `loading`, `loaded`, and `error` instead of deriving health from a non-empty model string.
- [x] Return useful health details: active model, worker alive, last load error, last load duration, uptime.
- [x] Add tests for startup failure, timeout, worker crash, and failed model switch.
- [x] Update `packages/protocol/openapi.yaml` after response fields change.

Relevant files:
- `apps/server/phonos_server/models.py`
- `apps/server/phonos_server/main.py`
- `apps/server/tests/test_api.py`
- `packages/protocol/openapi.yaml`

Acceptance criteria:
- `/health` never reports `ok` when the worker process is missing or dead.
- A failed model switch does not leave the server claiming the new model is loaded.
- Tests cover both successful and failed model switches.

#### Align transcription timeout behavior

- [x] Make server request timeout configurable with `PHONOS_TRANSCRIBE_TIMEOUT_SECONDS`.
- [x] Make the macOS client timeout long enough to match the server default.
- [x] Return a distinct `504` timeout error from the server when transcription exceeds the configured limit.
- [x] Show a user-facing timeout message that suggests using a smaller model or increasing the timeout. *(1.2.0)*
- [x] Add server tests for timeout responses.

Relevant files:
- `apps/server/phonos_server/models.py`
- `apps/server/phonos_server/config.py`
- `apps/macos/Sources/ServerClient.swift`
- `apps/macos/Sources/SettingsView.swift`

Acceptance criteria:
- The client no longer gives up at 120s while the server continues working for up to 600s.
- Timeout errors are distinguishable from network failures and generic server failures.

#### Limit upload size and stream audio safely

- [x] Add `PHONOS_MAX_UPLOAD_MB` with a conservative default.
- [x] Reject oversized requests with `413 Payload Too Large`.
- [x] Stream uploads to a temp file instead of reading the whole file into memory.
- [x] Validate extension and empty file behavior after streaming.
- [x] Add server tests for empty files, valid files, unsupported files, and oversized uploads.
- [x] Document upload limits in README, deployment docs, and OpenAPI.

Relevant files:
- `apps/server/phonos_server/transcription.py`
- `apps/server/phonos_server/config.py`
- `apps/server/tests/test_api.py`
- `packages/protocol/openapi.yaml`
- `README.md`
- `docs/deployment.md`

Acceptance criteria:
- Large uploads cannot exhaust server memory.
- Oversized uploads return `413` with a clear JSON error.

#### Delete temporary recordings on macOS

- [x] Delete recorded temp WAV files after a successful or failed upload.
- [x] Ensure deletion happens in all paths: success, server error, auth error, timeout, paste failure, empty transcript, **and stopRecording write failures**.
- [ ] Keep an optional debug setting only if needed for troubleshooting. (low priority)
- [ ] Add logging or debug-only diagnostics for cleanup failures. (low priority)

Relevant files:
- `apps/macos/Sources/AudioRecorder.swift`
- `apps/macos/Sources/MenuBarController.swift`

Acceptance criteria:
- Repeated dictation sessions do not accumulate `phonos_recording_*.wav` files in the temp directory.
- Cleanup does not delete an active recording.

### P1 — Security and Professional Release Quality

#### Store auth token in Keychain

- [x] Replace `@AppStorage("authToken")` with a Keychain-backed storage helper.
- [x] Migrate any existing token from `UserDefaults` to Keychain on first launch after upgrade.
- [x] Clear the old `UserDefaults` token after successful migration.
- [x] Keep SwiftUI settings binding behavior simple and predictable.
- [x] Add error handling for Keychain read/write failures.

Relevant files:
- `apps/macos/Sources/SettingsManager.swift`
- `apps/macos/Sources/SettingsView.swift`
- `apps/macos/Sources/ServerClient.swift`

Acceptance criteria:
- Auth tokens are no longer persisted in plain `UserDefaults`.
- Existing users keep their configured token after upgrading.

#### Add proper first-run setup

- [x] Add a first-run window or checklist covering microphone permission, accessibility permission, server URL, auth token, and connection test.
- [x] Detect missing microphone permission before the first recording attempt.
- [x] Detect missing Accessibility permission before paste automation fails.
- [x] Add direct buttons to open the relevant macOS privacy settings panes.
- [x] Store first-run completion state, but allow reopening setup from the menu.
- [x] Add model choice to the first-run setup.

Relevant files:
- `apps/macos/Sources/PhonosApp.swift`
- `apps/macos/Sources/MenuBarController.swift`
- `apps/macos/Sources/SettingsView.swift`
- `apps/macos/Sources/AudioRecorder.swift`
- `apps/macos/Sources/PasteEngine.swift`

Acceptance criteria:
- A new user can configure Phonos without reading docs first.
- Missing permissions are surfaced before the user loses a dictation.

#### Improve distribution polish

- [x] Add launch-at-login support.
- [ ] Add a stable signing/notarization path for Developer ID releases.
- [ ] Keep ad-hoc signing available for local development builds.
- [ ] Add a consistent bundle identifier and release metadata.
- [ ] Consider Sparkle or another update mechanism for signed releases.
- [ ] Document release steps and required signing environment variables.

Relevant files:
- `apps/macos/build.sh`
- `.github/workflows/ci.yml`
- `README.md`
- `docs/deployment.md`

Acceptance criteria:
- Release builds can be signed and notarized without manual local steps.
- Users do not need quarantine workarounds for official releases.

### P1 — User Experience and Workflow

#### Add richer menu-bar state feedback

- [x] Add distinct status states: idle, recording, transcribing, pasted, copied-only, and error.
- [x] Update menu item titles while work is in progress.
- [x] Disable conflicting actions during recording or transcription. *(1.2.0)*
- [ ] Add a short success/error notification or menu subtitle after each transcription.
- [x] Keep the last error available in the menu for troubleshooting. *(1.2.0)*

Relevant files:
- `apps/macos/Sources/MenuBarController.swift`
- `apps/macos/Sources/ServerClient.swift`
- `apps/macos/Sources/PasteEngine.swift`

Acceptance criteria:
- After recording stops, the user can tell whether Phonos is uploading, transcribing, pasting, or failed.
- Long transcriptions do not look like the app has gone idle.

#### Handle audio write failures explicitly

- [x] Stop swallowing `AVAudioFile.write` failures in the audio tap.
- [x] Capture write errors from the tap and surface them when stopping or during recording.
- [x] Stop recording safely if disk/write errors occur.
- [x] Add user-facing messages for microphone, file write, and engine failures.

Relevant files:
- `apps/macos/Sources/AudioRecorder.swift`
- `apps/macos/Sources/MenuBarController.swift`

Acceptance criteria:
- Corrupt or unwritable recordings fail with a specific local error before upload.

#### Add cancellation and recovery

- [ ] Add a way to cancel an in-progress transcription from the menu.
- [ ] Cancel the client request when the user cancels.
- [ ] Decide server behavior for cancellation: leave worker running, add request IDs, or move to a cancellable worker protocol.
- [ ] Make the UI recover cleanly after cancellation.

Relevant files:
- `apps/macos/Sources/MenuBarController.swift`
- `apps/macos/Sources/ServerClient.swift`
- `apps/server/phonos_server/models.py`
- `apps/server/phonos_server/transcription.py`

Acceptance criteria:
- Users can recover from a too-large recording or too-slow model without quitting the app.

#### Improve transcript history

- [ ] Decide whether history is session-only or optionally persistent.
- [ ] Add a privacy setting for persistent history.
- [ ] Store metadata with each transcript: created time, model, language, audio duration, processing time, paste/copy result.
- [ ] Add search/filter in the history window.
- [ ] Add per-entry actions: copy, paste, delete.
- [ ] Add clear-all confirmation for persistent history.

Relevant files:
- `apps/macos/Sources/TranscriptHistory.swift`
- `apps/macos/Sources/MenuBarController.swift`
- `apps/macos/Sources/SettingsView.swift`

Acceptance criteria:
- Users can find, reuse, and delete recent dictations without leaving unclear privacy behavior.

#### Improve model selection UX

- [x] Add model metadata to server responses or a client-side model catalog.
- [x] Show speed, language support, and recommended use for each model.
- [x] Warn before switching to very large models on CPU.
- [ ] Show model loading progress/state while switching.
- [ ] Disable transcription during model switching or queue it intentionally.

Relevant files:
- `apps/server/phonos_server/config.py`
- `apps/server/phonos_server/main.py`
- `apps/macos/Sources/SettingsView.swift`
- `packages/protocol/openapi.yaml`

Acceptance criteria:
- Users can choose a model based on expected performance, not only the model name.

#### Improve network discovery

- [x] Support interfaces beyond `en0` and `en1`.
- [ ] Handle non-`/24` local networks.
- [ ] Add a Tailscale-specific discovery path or documented MagicDNS flow.
- [ ] Show scan progress and partial results.
- [x] Avoid launching 254 simultaneous requests without a concurrency limit.

Relevant files:
- `apps/macos/Sources/NetworkScanner.swift`
- `apps/macos/Sources/SettingsView.swift`
- `docs/deployment.md`

Acceptance criteria:
- Network scan works on common Wi-Fi, Ethernet, and Tailscale setups or clearly explains why it cannot.

### P2 — Observability, Testing, and Protocol Discipline

#### Add server observability

- [x] Track uptime, request count, transcription count, last error, current model, and last processing duration.
- [x] Add `/metrics` or an expanded `/health` response.
- [x] Ensure auth-sensitive values are never logged or returned.
- [ ] Add structured logs for model load, transcription start/end, timeout, and worker restart.

Relevant files:
- `apps/server/phonos_server/main.py`
- `apps/server/phonos_server/models.py`
- `apps/server/phonos_server/transcription.py`
- `packages/protocol/openapi.yaml`

Acceptance criteria:
- A deployment owner can diagnose “offline,” “busy,” “model loading,” and “last transcription failed” without SSHing into the process first.

#### Strengthen tests around real failure modes

- [x] Add tests for model worker load failure and worker death.
- [x] Add tests for upload size limit and streaming upload behavior.
- [x] Add tests for auth on all protected endpoints.
- [x] Add OpenAPI contract checks for response shapes. *(1.2.0)*
- [x] Add Swift unit tests where feasible for URL building, error decoding, and settings storage. *(1.2.0: KeychainStore + ServerClient)*
- [x] Add a lightweight end-to-end smoke test for the server container. *(1.2.0)*

Relevant files:
- `apps/server/tests/test_api.py`
- `apps/server/tests/conftest.py`
- `packages/protocol/openapi.yaml`
- `.github/workflows/ci.yml`

Acceptance criteria:
- CI covers the failure modes most likely to break a real user after v1.

#### Keep docs honest and professional

- [x] Audit README, architecture, deployment, and roadmap for claims that are not implemented.
- [x] Replace overclaimed checklist items with explicit future tasks.
- [x] Decide how much of the current joke-heavy README tone belongs in the project long term.
- [x] Add a short privacy/security section that explains local processing, auth, temp files, logs, and history behavior.
- [x] Add a troubleshooting table for common user-facing errors.

Relevant files:
- `README.md`
- `docs/architecture.md`
- `docs/deployment.md`
- `docs/roadmap.md`

Acceptance criteria:
- A new user or contributor can trust that documented features match shipped behavior.

### P3 — Future Capability

#### Streaming transcription mode

---

## Phase 10: The Test Release (v1.2.0)

**Goal**: Close the testing gap on the macOS side, add E2E coverage, and ship small UX improvements that improve troubleshooting.

### 10.1 Swift Unit Tests

- [x] Unit tests for `KeychainStore` — read, write, delete, migration from `UserDefaults`
- [x] Unit tests for `ServerClient` — URL construction with/without token, error decoding, timeout behavior
- [x] Unit tests for `ModelCatalog` — verify guidance data integrity

### 10.2 E2E Smoke Test

- [x] Docker Compose server + real WAV → assert non-empty transcription
- [x] Run in CI alongside existing server tests
- [x] Docs: `apps/server/tests/test_e2e.py` with `pytest.mark.e2e`

### 10.3 OpenAPI Contract Validation

- [x] Verify server response shapes match `packages/protocol/openapi.yaml`
- [x] Catch drift between spec and implementation in CI

### 10.4 UX Improvements

- [x] Disable record/toggle actions during active recording or transcription
- [x] Show last error message in menu bar for post-failure troubleshooting
- [x] Display a user-facing timeout message when transcription exceeds server limit

### P3 — Future Capability

#### Streaming transcription mode

- [ ] Design a WebSocket protocol for audio chunks, partial transcripts, final transcripts, errors, and cancellation.
- [ ] Add server-side chunk handling and VAD strategy.
- [ ] Add client-side chunk streaming from `AVAudioEngine`.
- [ ] Add live transcript preview.
- [ ] Paste final transcript only after completion.
- [ ] Compare latency and quality against current upload mode before making it default.

Relevant files:
- `apps/server/phonos_server/main.py`
- `apps/server/phonos_server/transcription.py`
- `apps/macos/Sources/AudioRecorder.swift`
- `apps/macos/Sources/MenuBarController.swift`
- `packages/protocol/openapi.yaml`

Acceptance criteria:
- Streaming mode materially lowers perceived latency without making the reliable upload mode worse.
