<div align="center">


# Phonos

**Local dictation for macOS, powered by your own Whisper server.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-333?style=flat-square)]()
[![Python](https://img.shields.io/badge/python-3.12+-3776AB?style=flat-square&logo=python&logoColor=fff)]()

A self-hosted dictation tool that keeps audio on hardware you control. Press a
hotkey, speak, and Phonos pastes the transcript into the app you were using.

</div>

---

## Why Phonos?

| Cloud dictation | Phonos |
|---|---|
| Audio is processed by a remote service | Audio is sent only to your configured server |
| Usually subscription-based | Free and open source |
| Latency depends on internet and vendor load | Latency depends on your chosen hardware/model |
| One model fits all | Pick the model for your hardware |
| Vendor behavior is opaque | Server and client code are auditable |

---

## How it works

1. **Press a hotkey** - hold it down or toggle recording.
2. **Speak** - the Mac app records microphone audio.
3. **Transcribe** - the server runs `faster-whisper` in a dedicated subprocess.
4. **Paste** - the transcript is pasted into the previously active app, with clipboard fallback.

---

## Architecture

The server runs the active Whisper model in a dedicated subprocess. The main
FastAPI process communicates with that worker through local queues. When you
switch models via `PUT /models/active`, the old worker is stopped and a new
worker is started with the requested model, allowing the operating system to
reclaim model memory cleanly.

The server is intended for localhost, LAN, or private-network use such as
Tailscale. Set `PHONOS_AUTH_TOKEN` before exposing it beyond localhost.

---

## Quick start

### Server

```bash
git clone https://github.com/jb381/phonos && cd phonos/apps/server
cp .env.example .env          # optional: set PHONOS_AUTH_TOKEN
docker compose up -d          # transcription server on :8765
```

Without Docker:

```bash
uv sync
uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

### macOS client

**From a release** — download the latest `Phonos-*.dmg` from the [Releases](https://github.com/jb381/phonos/releases) page, open it, and drag `Phonos.app` to Applications.

**From source:**
```bash
cd apps/macos
./build.sh                    # creates Phonos.dmg and Phonos.app
open Phonos.dmg               # then drag to Applications
```

Releases are triggered by `git tag vX.Y.Z && git push --tags`. CI builds,
ad-hoc signs, and publishes a DMG automatically.

> Current release builds are ad-hoc signed and not notarized. Gatekeeper may
> require right-clicking the app and choosing **Open**, or using **Open Anyway**
> in System Settings -> Privacy & Security. Accessibility permission may need to
> be re-granted after ad-hoc rebuilds.
>
> To remove the quarantine attribute from the terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Phonos.app
> ```

---

## Features

- Menu-bar app with workflow status
- Global hotkey, defaulting to Control-Space
- Hold-to-record and toggle recording modes
- Direct paste into the previously active application
- Clipboard fallback when Accessibility permission is not granted
- First-run setup for permissions and server connection
- Model selector with live switching from the server
- Recent transcript history in the menu bar

---

## Requirements

| Component    | What you need                              |
|--------------|--------------------------------------------|
| Server       | Docker, a CPU, or a supported GPU          |
| Client       | macOS 14+, Xcode 15+                       |
| Network      | [Tailscale](https://tailscale.com) or same LAN |

---

## API

| Method | Path             | Purpose                    |
|--------|------------------|----------------------------|
| GET    | `/health`        | Server health + model info |
| GET    | `/models`        | List configured models     |
| GET    | `/models/active` | Get currently loaded model |
| PUT    | `/models/active` | Switch active model        |
| POST   | `/transcribe`    | Transcribe audio           |

`PUT /models/active` and `POST /transcribe` require auth when `PHONOS_AUTH_TOKEN` is set.

---

## Server config

```env
PHONOS_AUTH_TOKEN=          # leave empty to skip auth

PHONOS_MODEL=base.en
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3

PHONOS_DEVICE=cpu
PHONOS_COMPUTE_TYPE=int8
PHONOS_VAD_FILTER=true
PHONOS_TRANSCRIBE_TIMEOUT_SECONDS=600
PHONOS_MAX_UPLOAD_MB=100
```

Docker Compose binds to `127.0.0.1` by default. For remote access, set `PHONOS_BIND=0.0.0.0` and `PHONOS_AUTH_TOKEN`.

---

## Models

All models are English-optimized. Larger models are more accurate but slower and need more memory.

| Model             | Params | Notes                                 |
|-------------------|--------|---------------------------------------|
| `tiny.en`         | 39M    | Fastest, lowest memory                  |
| `base.en`         | 74M    | Fast, decent English quality           |
| `small.en`        | 244M   | Good quality/speed; recommended CPU daily driver |
| `medium.en`       | 769M   | Better accuracy, handles harder speech |
| `turbo`           | 798M   | Speed-optimized, multilingual          |
| `distil-large-v3` | 756M   | Distilled large, strong English        |
| `large-v3`        | 1550M  | Highest quality, very slow on CPU      |

Start with `small.en` for CPU usage. Try `turbo` or `distil-large-v3` if you
need higher quality or multilingual transcription. Use `large-v3` only when the
server has enough CPU/GPU capacity and memory.

---

## License

MIT.
