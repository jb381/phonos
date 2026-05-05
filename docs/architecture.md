# Phonos Architecture

## Overview

Phonos is a two-component local dictation system:

1. **Server** — runs on a capable machine (server/NAS/desktop), handles Whisper transcription.
2. **Mac Client** — native macOS menu-bar app that captures microphone audio and sends it to the server.

Components communicate over Tailscale or local network. No traffic leaves the LAN.

## System Diagram

```
┌─────────────────────┐         HTTP/HTTPS         ┌─────────────────────┐
│    Mac Client       │ ──────────────────────────> │    Server           │
│                     │                             │                     │
│  ┌───────────────┐  │  GET /health                │  FastAPI (uvicorn)  │
│  │ Menu Bar UI   │  │  GET /models                │                     │
│  └───────┬───────┘  │  PUT /models/active         │  ┌───────────────┐  │
│          │          │  POST /transcribe           │  │ faster-whisper│  │
│  ┌───────┴───────┐  │                             │  │ (CPU/GPU)     │  │
│  │ Audio Capture │  │  <── multipart audio        │  └───────────────┘  │
│  └───────────────┘  │      ───> json transcript   │                     │
│                     │                             │  Docker container   │
│  ┌───────────────┐  │                             │  (on server host)   │
│  │ Global Hotkey │  │                             └─────────────────────┘
│  └───────────────┘  │
│                     │
│  ┌───────────────┐  │
│  │ Paste Engine  │  │
│  └───────────────┘  │
└─────────────────────┘
```

## Components

### Server (`apps/server`)

**Tech**: Python 3.11+, FastAPI, uvicorn, faster-whisper

**Endpoints**:

| Method | Path              | Purpose                            |
|--------|-------------------|------------------------------------|
| GET    | `/health`         | Server health + model info         |
| GET    | `/models`         | List configured models             |
| GET    | `/models/active`  | Get currently loaded model         |
| PUT    | `/models/active`  | Switch active model                |
| POST   | `/transcribe`     | Transcribe uploaded audio file     |

**Default Configuration**:

```env
PHONOS_AUTH_TOKEN=
PHONOS_MODEL=base.en
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3
PHONOS_DEVICE=cpu
PHONOS_COMPUTE_TYPE=int8
PHONOS_VAD_FILTER=true
PHONOS_TRANSCRIBE_TIMEOUT_SECONDS=600
PHONOS_MAX_UPLOAD_MB=100
```

**Model Lifecycle**:

- On startup, the configured default model is loaded.
- `PUT /models/active` triggers model switch: old model is unloaded, new model is loaded.
- Model loading is gated behind a lock to prevent concurrent mutation during transcription.
- Models are cached locally by `faster-whisper`.

### Mac Client (`apps/macos`)

**Tech**: Swift 5.9+, SwiftUI, AppKit

**Features**:

- Menu-bar status item
- Server URL + token configuration
- Health check and connection status display
- Model selector (fetched from server)
- Hold-to-record and toggle recording modes
- Global hotkey: attempt `Fn`/`Globe`, fallback to left `Control`
- Direct paste into active application
- Transcript preview in menu

**Permissions Required**:

- Microphone — for audio capture
- Accessibility — for global hotkey event tap and paste automation

**Audio Flow**:

1. Hotkey triggers recording start.
2. `AVAudioEngine` captures microphone to temp WAV file.
3. On recording stop, audio is uploaded to `POST /transcribe`.
4. Server returns transcript JSON.
5. Transcript is pasted into frontmost application via clipboard + simulated `Cmd+V`.

### Protocol (`packages/protocol`)

Shared OpenAPI 3.0 specification defining the client-server contract.
Validated by both server and client during development.

## Network Model

```
Mac client ──> server-tailnet-hostname:8765
```

- Server binds to `0.0.0.0:8765` inside Docker, exposed to host.
- Mac connects via Tailscale MagicDNS name or Tailscale IP.
- Optional `PHONOS_AUTH_TOKEN` provides application-level auth.
- No public internet exposure — intended as a LAN/Tailscale-only service.

## Data Flow (MVP — Upload)

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Hotkey   │ ──> │ Audio    │ ──> │ Server   │ ──> │ Paste    │
│ triggers │     │ Capture  │     │ Transcr. │     │ to App   │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                      │                │
                   WAV file        JSON {text}
```

## Future: Streaming Mode

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Hotkey   │ ──> │ Audio    │ ──> │ WebSocket│ ──> │ Live     │
│ triggers │     │ Chunks   │     │ Stream   │     │ Preview  │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
                                      │
                                  Partial transcripts
                                  Final transcript
                                      │
                                  ┌──────────┐
                                  │ Paste    │
                                  └──────────┘
```
