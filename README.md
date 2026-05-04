# Phonos

Local-first dictation tool — a Whisper Flow style application.

**Server** runs on a local machine with `faster-whisper` for offline transcription.
**Mac client** is a native menu-bar app with a global hotkey for hands-free dictation.
Both communicate over Tailscale or local network — no cloud dependency.

## Monorepo Structure

```
phonos/
  apps/
    server/       # Python FastAPI server with faster-whisper
    macos/        # Native macOS SwiftUI/AppKit menu-bar app
  packages/
    protocol/     # Shared OpenAPI spec
  docs/           # Architecture, roadmap, deployment guides
```

## Quick Start

### Server

```bash
cd apps/server
cp .env.example .env
uv sync --no-dev
uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

### Mac Client

Open `apps/macos/Phonos.xcodeproj` in Xcode, build, and run.

Configure server URL in the menu-bar app settings.

## Requirements

- **Server**: Docker, Python 3.11+, or just Docker
- **Client**: macOS 14+ (Sonoma)
- **Network**: Tailscale preferred, direct LAN works too
- **Permissions**: Microphone and Accessibility (for paste)
