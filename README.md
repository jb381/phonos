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
3. **Whisper transcribes** — your server runs `faster-whisper`, fully offline.
4. **Text appears** — pasted directly into whatever app you're using.

---

## Quick start

### Server (on your server / Docker host)

```bash
git clone https://github.com/jb381/phonos && cd phonos/apps/server
cp .env.example .env        # optional: set PHONOS_AUTH_TOKEN
docker compose up -d        # boom, transcription server on :8765
```

Check it works:

```bash
curl http://localhost:8765/health
```

Run without Docker:

```bash
uv sync
uv run uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

Run tests:

```bash
uv run pytest
```

### macOS Client

```bash
cd apps/macos

# Build and launch the app bundle (recommended)
./build.sh
open .build/Phonos.app

# Or run directly during development
swift build
swift run Phonos
```

`swift run Phonos` is useful during development, but `./build.sh` creates the app bundle with the permission usage descriptions macOS expects.

When first launched, grant:
- **Microphone** — to capture audio for transcription
- **Accessibility** — for paste automation

Both in `System Settings → Privacy & Security`.

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

| Component | What you need |
|-----------|--------------|
| Server    | Docker, a CPU (or GPU if you're fancy) |
| Client    | macOS 14+, Xcode 15+ |
| Network   | [Tailscale](https://tailscale.com) (easy) or same LAN |
| Permissions | Microphone 🎤 + Accessibility ♿ |

---

## API

| Method | Path             | Purpose                        |
|--------|------------------|--------------------------------|
| GET    | `/health`        | Server health + model info     |
| GET    | `/models`        | List configured models         |
| GET    | `/models/active` | Get currently loaded model     |
| PUT    | `/models/active` | Switch active model            |
| POST   | `/transcribe`    | Transcribe uploaded audio file |

---

## Server config

```env
# .env
PHONOS_HOST=0.0.0.0
PHONOS_BIND=127.0.0.1
PHONOS_PORT=8765
PHONOS_AUTH_TOKEN=

PHONOS_MODEL=base.en
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3

PHONOS_DEVICE=cpu
PHONOS_COMPUTE_TYPE=int8
PHONOS_VAD_FILTER=true
```

Docker Compose binds to `127.0.0.1` by default. If another machine needs to reach the server, set `PHONOS_BIND=0.0.0.0` and configure `PHONOS_AUTH_TOKEN`.

---

## Model Guide

All models are English-optimized. Larger models are more accurate but slower and need more memory.

| Model | Parameters | Strengths | Weaknesses | Best use |
|-------|------------|-----------|------------|----------|
| `tiny.en` | 39M | Fastest, lowest memory | Least accurate, struggles with noise/accents | Smoke tests, very weak hardware |
| `base.en` | 74M | Fast, decent English quality | Noticeably less accurate than `small.en` | Quick dictation baseline |
| `small.en` | 244M | Good quality/speed balance | Slower than `base.en` | **Recommended daily CPU dictation** |
| `medium.en` | 769M | Better accuracy, handles harder speech | Much slower and heavier | Accuracy-focused dictation |
| `turbo` | 798M | Newer speed-optimized Whisper, good quality | Multilingual; speed depends on hardware | Try when `small.en` is not accurate enough |
| `distil-large-v3` | ~756M | Faster distilled large model, strong English candidate | May be less robust than full `large-v3` | Try when `small.en` is not accurate enough |
| `large-v3` | 1550M | Highest quality, multilingual | Very slow on CPU, high memory | Only when quality matters more than latency |

For daily dictation, start with `small.en`. If it is not accurate enough, try `turbo` or `distil-large-v3`. Use `large-v3` only if you accept much slower CPU transcription.

---

## License

MIT — do whatever, just keep the Greek in the README.

---

<div align="center">

*made with ☕ and a mild obsession with terminal aesthetics*

</div>
