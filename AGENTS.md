# Agent Guide — Phonos

## When You Make Any Change

**Update the changelog.** Every change that affects users (features, fixes, deprecations, breaking changes) gets an entry in `CHANGELOG.md` under the correct section (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`). The changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Match the existing style — see `CHANGELOG.md` for examples.

## Working Rules

- Inspect the relevant code before changing it; do not guess from file names alone.
- Keep changes small and consistent with surrounding code.
- Do not commit, push, or revert unrelated work unless the user explicitly asks.

## Conventions

### Commits

Semantic commit messages. The convention used in this repo:

```
type(scope): short description

type: feat, fix, refactor, test, docs, chore, style, perf
scope: server, macos, protocol, repo
```

Example: `feat(macos): add microphone input device selector`

### Versioning

Follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Versions are tracked in `CHANGELOG.md`. Releases are triggered by `git tag vX.Y.Z && git push --tags` — CI builds, signs, and publishes.

### Code Style

- **Python (server):** Ruff linter config at `apps/server/ruff.toml`. Line length 100, target 3.11, rules I/F/E/W/B/SIM. Run `uv run ruff check .` before committing.
- **Swift (macOS):** Match existing patterns. No explicit style guide — stay consistent with surrounding code.

## Architecture (tl;dr)

```
macOS app (Swift) ──HTTP──> Python server (FastAPI + faster-whisper)
```

- **macOS app:** Menu-bar app. `AVAudioEngine` captures mic → WAV → `POST /transcribe` → `Cmd+V` paste.
- **Server:** FastAPI on port 8765. Whisper in a subprocess (`multiprocessing.Process`). Model switches kill & restart the process so memory is reclaimed.
- **Protocol:** OpenAPI 3.0 spec at `packages/protocol/openapi.yaml`.

## Build & Test

### macOS client

```bash
cd apps/macos
swift build           # debug build
swift test            # unit tests (Keychain tests skipped unless PHONOS_TEST_KEYCHAIN=1)
./build.sh            # release build → Phonos.dmg
```

### Python server

```bash
cd apps/server
uv sync
uv run ruff check .
uv run pytest -m "not e2e"    # unit tests only
uv run pytest -m e2e          # requires Docker Compose up
uv run pytest                 # all tests
```

### CI

Jobs: `python` (unit tests + ruff), `e2e`, `server-image`, and `swift` (test + build DMG). On push, CI publishes the server Docker image to `ghcr.io/jb381/phonos-server`; on tag push, it also creates a GitHub Release with the DMG.

## Testing

- **Server tests:** `apps/server/tests/`. Use `pytest` with FastAPI `TestClient`. Mock the model worker (`conftest.py`). OpenAPI contract validation in `test_openapi_contract.py`.
- **macOS tests:** `apps/macos/Tests/`. Use `MockURLProtocol` for network tests. Keychain tests require `PHONOS_TEST_KEYCHAIN=1` (skipped in CI).
- **E2E:** `test_e2e.py` with `@pytest.mark.e2e` — spins up real Docker Compose with `tiny.en` model.
- Aim for good coverage. When fixing bugs, add a test that would have caught it.

## Pull Requests

- Open PRs from branches, not forks (unless external contributor).
- For UI changes, include screenshots in the PR body.
- PR titles should match commit style.
- Reference the changelog entry in the PR description.

## Key Files

| File | What it is |
|---|---|
| `apps/server/phonos_server/main.py` | FastAPI app, 5 endpoints |
| `apps/server/phonos_server/models.py` | Whisper subprocess lifecycle |
| `apps/server/phonos_server/transcription.py` | Upload handling & validation |
| `apps/server/phonos_server/config.py` | All `PHONOS_*` env vars |
| `apps/server/phonos_server/auth.py` | Bearer token auth |
| `apps/macos/Sources/PhonosApp.swift` | `@main` entry point |
| `apps/macos/Sources/MenuBarController.swift` | Menu bar, state, orchestration |
| `apps/macos/Sources/RecordingSession.swift` | Record → transcribe → paste state machine |
| `apps/macos/Sources/AudioRecorder.swift` | AVAudioEngine mic capture |
| `apps/macos/Sources/AudioDeviceManager.swift` | CoreAudio input device selection |
| `apps/macos/Sources/SettingsManager.swift` | Settings + Keychain auth token |
| `apps/macos/Sources/ServerClient.swift` | HTTP client for all server endpoints |
| `apps/macos/Sources/PasteEngine.swift` | Cmd+V paste + clipboard |
| `apps/macos/Sources/SettingsView.swift` | Settings UI |
| `apps/macos/Sources/FirstRunView.swift` | Setup wizard |
| `packages/protocol/openapi.yaml` | Client-server contract |

## Important Details

- macOS app uses `.accessory` activation policy (no dock icon — menu bar only).
- `NSAllowsArbitraryLoads = true` in Info.plist — required because server URLs are user-configured (Tailscale IPs like `100.x.x.x`).
- Auth token lives in macOS Keychain, not UserDefaults. Migration from UserDefaults is handled in `SettingsManager.init()`.
- Server transcription is serialized (`asyncio.Semaphore(1)` + threading lock on ModelManager) — only one request at a time.
- Audio uploads are streamed to temp files on both sides to bound memory.
