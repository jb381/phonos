# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - Unreleased

**Quality-of-Life and Hardening Release**

### Fixed

- Made server model loading transactional so `/health` and `/models/active` no longer report a model as loaded when worker startup failed.
- Added explicit model worker health, last load error, and model load timing to health responses.
- Aligned macOS and server transcription timeouts so the client no longer gives up after 120 seconds while the server continues processing.
- Limited server audio upload size and return `413` when an audio file exceeds the configured limit.
- Removed temporary macOS recording files after each transcription flow completes.
- Moved macOS auth token storage from `UserDefaults` to Keychain, with migration for existing saved tokens.
- Added a first-run setup window for microphone permission, Accessibility permission, server settings, and connection checks.
- Added menu-bar workflow status for recording, transcribing, pasting, copied-to-clipboard, and error states.

### Changed

- Added a post-1.0 implementation backlog to the roadmap with prioritized reliability, security, UX, observability, testing, and release-polish tasks.
- Corrected roadmap items that were marked complete but are still future work.
- Added `PHONOS_TRANSCRIBE_TIMEOUT_SECONDS` for configurable server-side transcription timeouts and return `504` when a transcription exceeds it.
- Added `PHONOS_MAX_UPLOAD_MB` and stream incoming audio uploads to disk instead of reading full files into memory.

## [1.0.0] - 2026-05-05

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
