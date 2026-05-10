# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-05-10 💾

### Added

- Persistent transcript history on macOS backed by a local SQLite database (`~/Library/Application Support/Phonos/history.sqlite`) using GRDB.
- New transcript metadata persistence and display: model, language, audio duration, processing time, and timestamp.
- Search and filter controls in the macOS history window (free-text search plus model/language filters with reset state).
- Settings toggle to enable or disable local history persistence (`Save Transcription History`), enabled by default.
- New Swift tests for the history persistence layer (`TranscriptHistoryStoreTests`) covering database ordering, clearing, persistence gating, and toggle behavior.

### Changed

- `RecordingSessionDelegate` now receives the full `TranscriptionResponse` for transcript handling, so history capture includes all transcription metadata.
- Transcript history UI now reflects persisted state, including a disabled-state empty view, a Clear action that removes saved transcripts even while history is disabled, and richer per-entry metadata in the history window.

## [1.4.1] - 2026-05-09 🩹

### Fixed

- Restored the previously selected macOS system input device when recording startup fails, and added startup rollback cleanup for taps/temp files.
- Guarded server request handling against an uninitialized model manager so endpoints return a clean `503` instead of crashing.

### Added

- Added server regression tests for uninitialized-manager `503` behavior on `/models`, `/models/active`, `PUT /models/active`, and `/transcribe`.
- Added macOS `AudioRecorder` rollback tests and a minimal `AudioDeviceClient` test seam for deterministic startup/cleanup coverage.

---

## [1.4.0] - 2026-05-08 🎙️

### Added

- Replaced app icon and menu bar icons with a new brand identity — tackled with OpenAI ImageGen 2 until API limits were exhausted (hence the app icon is slightly bigger than ideal).
- Microphone input device selector in Settings: users can now choose a specific microphone from a picker, or leave it at "System Default".
- `AudioDeviceManager` utility wrapping CoreAudio to enumerate input devices, set the default input device, and query the current default.
- `AudioRecorder` now temporarily switches to the user-selected input device at recording start and restores the original device on stop.
- Settings now shows the running app version/build in the App section.
- `apps/macos/dev-run.sh` for local macOS development: builds a debug app bundle, ejects mounted Phonos DMGs, quits the running app, and launches the fresh build without creating a DMG.
- `docs/ui-todo.md` with a detailed plan for macOS UI polish and follow-up work.
- AGENTS.md with conventions, build/test commands, and architecture overview for agent contributors.
- "Working Rules" section to AGENTS.md (inspect before editing, keep changes small, no commits unless asked).

### Changed

- Replaced the Settings `Form` with a tighter fixed-height, non-scrollable settings pane using a shared aligned layout and fixed label column.
- Connection status now shows text beside the dot (`Connected`, `Loading model`, or the current error) instead of relying on a lone colored indicator.
- Settings pickers now hide their internal labels and use stable widths so recording, microphone, shortcut, and model controls align to the same content column.
- Setup now uses the same connection/model sections as Settings, labels server URL and auth token directly, and shows action-oriented connection status copy.
- Setup permissions now include a `Recheck` button for Accessibility, hide completed grant actions, and show a wrapping inline warning before Done when setup is incomplete.
- Menu-bar status labels are now user-facing, success statuses auto-reset after 3 seconds, and the idle status row is hidden.
- `Setup…` is renamed to `Setup Assistant…` after first run completes, and Settings/Setup Assistant menu items now use aligned SF Symbol icons.
- Transcript history rows use a smaller 8 pt corner radius, and the `Copy` text button is now a `doc.on.doc` icon button with tooltip.

### Fixed

- Model selection now keeps the currently selected model visible when the server model list cannot be fetched.
- Kept generated macOS app bundles writable by the owner so repeated local builds can replace bundled resources cleanly.
- Normalized leading `v` prefixes out of the app bundle version string while keeping release tags unchanged.
- Fixed CI job count in AGENTS.md: listed all four jobs (`python`, `e2e`, `server-image`, `swift`) instead of two.
- Updated Python server commands in AGENTS.md to use `uv run` prefix, matching CI.
- Updated Code Style ruff command in AGENTS.md to `uv run ruff check .`.

---

## [1.3.1] - 2026-05-07 ✨

**✨ Public Release Polish**

### Added

- Added GitHub Container Registry publishing for the server Docker image on `main` and release tags.
- Documented running the prebuilt server image from `ghcr.io/jb381/phonos-server`.

---

## [1.3.0] - 2026-05-07 🛡️

**🛡️ Reliability, Security, and Refactoring Release**

### Added

- Streamed audio upload in the macOS client by writing the multipart body to a temp file and using `URLSessionUploadTask`, keeping memory usage bounded regardless of recording length.
- Audio content validation on the server: `.wav` uploads are now checked for valid `RIFF/WAVE` magic bytes before being passed to the transcription worker.
- Disk-space check before recording on macOS: warns immediately if fewer than 100 MB are available on the temp volume.
- Concurrency guard on the server: transcription requests are gated by an `asyncio.Semaphore(1)` so only one transcription runs at a time.
- `WorkflowStatus` enum in the macOS app to replace stringly-typed workflow state.
- `RecordingSession` actor that owns the recording → transcribing → pasting state machine, extracted from `MenuBarController`.
- `ServerSettingsViewModel` that centralizes server health, model fetching, and model switching logic, shared by `FirstRunView` and `SettingsView`.
- First-run completion warning when the user clicks Done without microphone permission or a verified server connection.
- Added `stop_grace_period: 90s` to the Docker Compose service so in-flight transcriptions can finish during redeploys.
- Added security note in `docs/deployment.md` explaining the App Transport Security trade-off.
- Added shared `tests/utils.py` for server test fixtures.
- Added server tests for short-circuit model loading and invalid WAV headers.

### Changed

- Hardened App Transport Security exception in macOS build with an inline comment documenting why `NSAllowsArbitraryLoads` is necessary for arbitrary user-configured server URLs.
- Moved the global HTTP request counter onto `ModelManager` and guarded it with `self._lock` for thread safety.
- OpenAPI `ErrorResponse` schema now documents `detail` (the FastAPI native key) instead of the non-standard `error` field.
- Switched DMG filesystem from HFS+ to APFS for modern macOS distribution.
- Aligned README Python version badge with build files: now shows `3.11+` instead of `3.12+`.
- `distil-large-v3` is now flagged as a large CPU model (756M parameters, comparable to `medium.en`).
- Debounced Keychain writes for the auth token by 0.3 s to avoid repeated writes on every keystroke.
- Documented the Keychain test strategy in `.github/workflows/ci.yml` and `KeychainStoreTests.swift`.

### Fixed

- Fixed Keychain token migration race condition: added a `keychainMigrationCompleted` flag so a crash between the Keychain write and the UserDefaults delete does not leave the plaintext token in insecure storage forever.
- Restored the user's previous clipboard contents after paste in `PasteEngine`.
- Rebuilt clipboard restoration from pasteboard data snapshots to avoid crashes when restoring provider-backed `NSPasteboardItem` objects.
- Prevented the menu-bar app from terminating when the last utility window closes.
- Removed stale `Fn`/`Globe` key reference from `docs/architecture.md`.
- Fixed duplicated `P3 — Future Capability` section in `docs/roadmap.md`.

---

## [1.2.1] - 2026-05-06 🌐

### Fixed

- Replaced `NSAllowsLocalNetworking` with `NSAllowsArbitraryLoads` in the macOS ATS configuration. The local-networking exception only covers RFC 1918 private ranges and .local domains, which blocks HTTP connections to Tailscale IPs (100.x.x.x) and some LAN setups.

---

## [1.2.0] - 2026-05-06 🧪

**🧪 The Test Release**

### Added

- macOS app icon for the menu bar and dock.
- Swift unit tests for KeychainStore (read, write, delete, migration from UserDefaults).
- Swift unit tests for ServerClient (URL building, auth headers, error decoding, timeout handling).
- Swift unit tests for ModelCatalog (guidance data integrity, model descriptions, large-model warnings).
- OpenAPI contract validation tests to keep the spec and server responses aligned.
- End-to-end smoke test with a Docker server container and a real WAV file.
- E2E test job in CI alongside existing server and client tests.
- Swift tests now run in CI.

### Changed

- Disabled conflicting menu actions during recording and transcription to prevent double-triggers.
- Kept the last error message visible in the menu bar for troubleshooting after a failure.
- Showed a user-facing timeout suggestion when transcriptions exceed the server limit.
- Server URL now auto-prepends `http://` when no scheme is provided, making it easier to enter IP addresses.
- Settings view now shows connection error text inline instead of only in a tooltip.

### Fixed

- Ensured temp recording cleanup runs even when `stopRecording()` throws a write error.
- Added App Transport Security exception (`NSAllowsLocalNetworking`) so HTTP connections to LAN/Tailscale servers work without requiring HTTPS.

---

## [1.1.0] - 2026-05-05 🔧

**🔧 Quality-of-Life and Hardening Release**

### Fixed

- Made server model loading transactional so `/health` and `/models/active` no longer report a model as loaded when worker startup failed.
- Added explicit model worker health, last load error, and model load timing to health responses.
- Aligned macOS and server transcription timeouts so the client no longer gives up after 120 seconds while the server continues processing.
- Limited server audio upload size and return `413` when an audio file exceeds the configured limit.
- Removed temporary macOS recording files after each transcription flow completes.
- Moved macOS auth token storage from `UserDefaults` to Keychain, with migration for existing saved tokens.
- Added a first-run setup window for microphone permission, Accessibility permission, server settings, and connection checks.
- Added menu-bar workflow status for recording, transcribing, pasting, copied-to-clipboard, and error states.
- Surfaced local audio file write failures instead of uploading a silently corrupt recording.
- Added a launch-at-login setting for the macOS app.
- Added model guidance in Settings and first-run setup, including warnings for slower CPU-heavy models.
- Improved network scanning to consider all active IPv4 interfaces and probe hosts in bounded batches.
- Expanded server health output with uptime, request count, transcription count, and last processing duration.
- Reworked the README to keep the original personality and emoji-heavy style while tightening product, privacy, and release-signing claims.
- Added README privacy/security notes and troubleshooting guidance.

### Changed

- Added a post-1.0 implementation backlog to the roadmap with prioritized reliability, security, UX, observability, testing, and release-polish tasks.
- Corrected roadmap items that were marked complete but are still future work.
- Added `PHONOS_TRANSCRIBE_TIMEOUT_SECONDS` for configurable server-side transcription timeouts and return `504` when a transcription exceeds it.
- Added `PHONOS_MAX_UPLOAD_MB` and stream incoming audio uploads to disk instead of reading full files into memory.

## [1.0.0] - 2026-05-05 🎙️

### Added

- Initial public release of Phonos, a local dictation stack for macOS backed by a self-hosted Whisper server.
- macOS menu-bar app with hold-to-record and toggle recording modes.
- Configurable global recording shortcut, defaulting to Control-Space.
- Settings window for server URL, auth token, recording mode, shortcut, server health, network scan results, and model selection.
- Microphone capture via `AVAudioEngine`, transcription upload, transcript history, and recent-transcript copy actions.
- Automatic paste into the previously active application through Accessibility APIs, with clipboard fallback when Accessibility permission is not granted.
- FastAPI transcription server powered by `faster-whisper`.
- Dedicated model subprocess management so model switches release memory cleanly.
- Model listing and live switching for `tiny.en`, `base.en`, `small.en`, `medium.en`, `turbo`, `distil-large-v3`, and `large-v3`.
- Optional bearer-token authentication for server endpoints.
- Docker and Docker Compose deployment for the transcription server.
- Shared OpenAPI protocol specification.
- GitHub Actions CI for server tests, linting, macOS builds, DMG artifacts, and tagged release publishing.

### Fixed

- Packaged macOS DMGs can open Settings without crashing when the shortcut recorder is shown.
- Release builds now use a full git checkout so the macOS build number reflects repository history instead of always reporting build `1`.

### Notes

- macOS builds are ad-hoc signed and not notarized. Gatekeeper may require right-click Open, Open Anyway in System Settings, or removing the quarantine attribute.
- Phonos runs locally on user-controlled hardware, but the macOS app still needs a running Phonos server reachable over localhost, LAN, or a private network such as Tailscale.
