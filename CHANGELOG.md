# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-04

### Added

- Initial release of Phonos — local, offline dictation tool.
- macOS menu-bar client with global hotkey (Control-Space) for push-to-talk and toggle recording.
- Audio capture via `AVAudioEngine` with automatic paste into the active application using Accessibility APIs.
- FastAPI transcription server running `faster-whisper` in dedicated subprocesses.
- Shared OpenAPI protocol spec between client and server.
- Support for multiple Whisper models (`tiny.en` through `large-v3`) with live switching.
- Docker deployment for the transcription server.
- GitHub Actions CI: automated builds, linting, tests, and DMG artifact generation.
- Ad-hoc code signing for macOS distribution.
