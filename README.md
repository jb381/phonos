<div align="center">


# 🎙️🗣️🔪 φόνος — phonos

*phónos — voice, sound, speech... but also murder, slaughter, homicide (yes, really)*

**Speak freely. Your words, where you need them.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-333?style=flat-square)]()
[![Python](https://img.shields.io/badge/python-3.12+-3776AB?style=flat-square&logo=python&logoColor=fff)]()

A *Whisper Flow*–style dictation tool that runs entirely on your own hardware.
Press a hotkey, talk, and watch your words appear in whatever app you're in.
No cloud. No subscriptions. No latency spikes when the Wi-Fi gets moody.

*Phonos slays the paid competition — your wallet will feel the difference.* ☠️

</div>

───

## 🗡️ Why Phonos?

The name means "murder" in Greek. We're not subtle about who we're coming for.

| ☁️ Cloud dictation (Otter, Rev, Whisper Flow et al.) | 🔪 Phonos |
|---|---|
| Your audio leaves your machine | Stays local, always |
| Subscription ($5–$30/mo) | Free, forever |
| Latency depends on your ISP | Bounded by your CPU |
| Privacy? lol | Open source, auditable |
| One model fits all | Pick the model for your hardware |
| VC-funded, may pivot/raise prices/enshittify | No investors to disappoint |

───

## ⚡ How it works

1. **Press a hotkey** — hold it down or toggle, your call.
2. **Talk** — your Mac captures the audio.
3. **Whisper transcribes** — your server runs `faster-whisper` in a dedicated subprocess, fully offline.
4. **Text appears** — pasted directly into whatever app you're using.

───

## 🏗️ Architecture

The server runs each Whisper model in its own **dedicated subprocess**. The main FastAPI process stays lean (~50 MB) and communicates with the worker via local message queues. When you switch models via `PUT /models/active`, the old subprocess is killed and a new one spawns with the requested model. The operating system reclaims **every byte** from the old process — Python heap, CTranslate2 mmap regions, ONNX runtime buffers. Nothing lingers. Switch from `medium.en` to `tiny.en` and RSS drops by ~2 GB, guaranteed.

This is the same pattern production ML serving systems use (one process per model instance), just without the Kubernetes waste 🔥

───

## 🚀 Quick start

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

**From a release** — download the latest `Phonos-*.dmg` from the [Releases](https://github.com/jb381/phonos/releases) page, open it, and drag `Phonos.app` to Applications.

**From source:**
```bash
cd apps/macos
./build.sh                    # creates Phonos.dmg and Phonos.app
open Phonos.dmg               # then drag to Applications
```

Releases are triggered by `git tag vX.Y.Z && git push --tags` — CI builds, signs (ad-hoc), and publishes a DMG automatically.

> **No Apple Developer account = ad-hoc signing.** Gatekeeper will complain on first launch — right-click the app and choose **Open**, or go to System Settings → Privacy & Security and click **Open Anyway**. Accessibility permission must be re-granted after each ad-hoc rebuild. Fork out $99/yr for an Apple Developer account and we can switch to proper Developer ID signing + notarization — contributions welcome.
>
> To silence Gatekeeper's whining from the terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Phonos.app
> ```
> *Yes, it's the macOS equivalent of "turn it off and on again." No, we don't have the $99 either.*

───

## ✨ Features

- 🎙️ Menu-bar status item (idle / recording)
- ⌨️ Global hotkey (Control-Space by default, customizable)
- 🎮 Hold-to-record and toggle recording modes
- 📋 Direct auto-paste into active application
- 🔄 Model selector with live switching from the server
- 📜 Recent transcript history in the menu bar

───

## 📋 Requirements

| Component    | What you need                              |
|--------------|--------------------------------------------|
| Server       | Docker, a CPU (or GPU if you're fancy 🧊) |
| Client       | macOS 14+, Xcode 15+                       |
| Network      | [Tailscale](https://tailscale.com) or same LAN |

───

## 📡 API

| Method | Path             | Purpose                    |
|--------|------------------|----------------------------|
| GET    | `/health`        | Server health + model info |
| GET    | `/models`        | List configured models     |
| GET    | `/models/active` | Get currently loaded model |
| PUT    | `/models/active` | Switch active model        |
| POST   | `/transcribe`    | Transcribe audio           |

`PUT /models/active` and `POST /transcribe` require auth when `PHONOS_AUTH_TOKEN` is set.

───

## 🔧 Server config

```env
PHONOS_AUTH_TOKEN=          # leave empty to skip auth

PHONOS_MODEL=base.en
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en,large-v3,turbo,distil-large-v3

PHONOS_DEVICE=cpu
PHONOS_COMPUTE_TYPE=int8
PHONOS_VAD_FILTER=true
```

Docker Compose binds to `127.0.0.1` by default. For remote access, set `PHONOS_BIND=0.0.0.0` and `PHONOS_AUTH_TOKEN`.

───

## 📊 Models

All models are English-optimized. Larger models are more accurate but slower and need more memory.

| Model             | Params | Notes                                 |
|-------------------|--------|---------------------------------------|
| `tiny.en`         | 39M    | Fastest, lowest memory 🏃              |
| `base.en`         | 74M    | Fast, decent English quality           |
| `small.en`        | 244M   | Good quality/speed — **recommended CPU daily driver** ✅ |
| `medium.en`       | 769M   | Better accuracy, handles harder speech |
| `turbo`           | 798M   | Speed-optimized, multilingual 🌍       |
| `distil-large-v3` | 756M   | Distilled large, strong English        |
| `large-v3`        | 1550M  | Highest quality, very slow on CPU 💀   |

Start with `small.en`. Not accurate enough? Try `turbo` or `distil-large-v3`. `large-v3` if you hate yourself.

───

## 📄 License

MIT — do whatever, just keep the Greek in the README. Preferably the murder one.

───

<div align="center">

*made with ☕, 🎧, a mild obsession with terminal aesthetics, and a name that apparently means murder*

</div>
