<div align="center">

# φωνή — phonos

*φωνή (phōnē) — voice, sound, speech*

**Speak freely. Your words, where you need them.**

A <em>Whisper Flow</em>–style dictation tool that runs entirely on your own hardware.
Press a hotkey, talk, and watch your words appear in whatever app you're in.
No cloud. No subscriptions. No latency spikes when the Wi-Fi gets moody.

</div>

---

## How it works

```
 ┌───────┐   hotkey   ┌──────────┐   audio   ┌──────────────┐   text   ┌──────────┐
 │  you  │ ────────→  │ phonos 🖥 │ ────────→ │ phonos 🖧     │ ──────→ │ any app  │
 │  🎙️   │            │  (macOS)  │  Tailscale │ (your server) │         │  ✨      │
 └───────┘            └──────────┘            └──────────────┘         └──────────┘
```

1. **Press a hotkey** — hold it down or toggle, your call.
2. **Talk** — your Mac captures the audio.
3. **Whisper transcribes** — your server runs `faster-whisper` in a dedicated subprocess, fully offline.
4. **Text appears** — pasted directly into whatever app you're using.

---

## Quick start

### Server

```bash
git clone https://github.com/jb381/phonos && cd phonos/apps/server
cp .env.example .env          # optional: set PHONOS_AUTH_TOKEN
docker compose up -d          # boom, transcription server on :8765
```

Without Docker:

```bash
uv sync
uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

### macOS client

```bash
cd apps/macos
./build.sh                    # creates app bundle with permissions
open .build/Phonos.app
```

Grant **Microphone** 🎤 and **Accessibility** ♿ in `System Settings → Privacy & Security`.

---

## Features

- Menu-bar status item (🎙️ idle / 🔴 recording)
- Global hotkey (Control-Space by default, customizable)
- Hold-to-record and toggle recording modes
- Direct auto-paste into active application
- Model selector with live switching from the server
- Recent transcript history in the menu bar

---

## Requirements

| Component    | What you need                              |
|--------------|--------------------------------------------|
| Server       | Docker, a CPU (or GPU if you're fancy)     |
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
```

Docker Compose binds to `127.0.0.1` by default. For remote access, set `PHONOS_BIND=0.0.0.0` and `PHONOS_AUTH_TOKEN`.

### Memory & model switching

Each model runs in its own subprocess. When you switch models via `PUT /models/active`, the old subprocess is killed and a new one starts with the requested model. The operating system reclaims all memory from the old process — so switching from `medium.en` back to `tiny.en` actually frees the ~2 GB, rather than keeping it around.

---

## Models

All models are English-optimized. Larger models are more accurate but slower and need more memory.

| Model             | Params | Notes                                 |
|-------------------|--------|---------------------------------------|
| `tiny.en`         | 39M    | Fastest, lowest memory                |
| `base.en`         | 74M    | Fast, decent English quality          |
| `small.en`        | 244M   | Good quality/speed — **recommended CPU daily driver** |
| `medium.en`       | 769M   | Better accuracy, handles harder speech |
| `turbo`           | 798M   | Speed-optimized, multilingual         |
| `distil-large-v3` | 756M   | Distilled large, strong English       |
| `large-v3`        | 1550M  | Highest quality, very slow on CPU     |

Start with `small.en`. Not accurate enough? Try `turbo` or `distil-large-v3`. `large-v3` if you hate yourself.

---

## License

MIT — do whatever, just keep the Greek in the README.

---

<div align="center">

*made with ☕ and a mild obsession with terminal aesthetics*

</div>
