<div align="center">


# 🎙️🗣️🔪 φόνος — phonos

*phónos — voice, sound, speech... but also murder, slaughter, homicide (yes, really)*

**Speak freely. Your words, where you need them.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-333?style=flat-square)]()
[![Release](https://img.shields.io/github/v/release/jb381/phonos?style=flat-square&label=release)](https://github.com/jb381/phonos/releases)
[![Status](https://img.shields.io/badge/status-beta-orange?style=flat-square)]()
[![Python](https://img.shields.io/badge/python-3.11+-3776AB?style=flat-square&logo=python&logoColor=fff)]()

A *Whisper Flow*–style dictation tool that runs entirely on hardware you control.
Press a hotkey, talk, and watch your words appear in whatever app you're in.
No cloud. No subscriptions. No mystery box between your microphone and your text.

**Beta:** usable for local/Tailscale dictation, but still early and ad-hoc signed.

*Phonos slays subscription dictation — your wallet gets to stay alive.* ☠️

</div>

───

## 🗡️ Why Phonos?

The name means "murder" in Greek. We are keeping the bit, just making the
software around it more serious.

| ☁️ Cloud dictation | 🔪 Phonos |
|---|---|
| Audio is processed by a remote service | Audio goes only to your configured server |
| Subscription required | Free and open source |
| Latency depends on internet and vendor load | Bounded by your hardware and model choice |
| One model fits all | Pick the model for your hardware |
| Vendor behavior is opaque | Open source and auditable |
| Surprise product decisions | You run the thing |

───

## ⚡ How it works

1. **Press a hotkey** — hold it down or toggle, your call.
2. **Talk** — your Mac captures the audio.
3. **Whisper transcribes** — your server runs `faster-whisper` in a dedicated subprocess.
4. **Text appears** — pasted directly into the app you were using, with clipboard fallback.

───

## 🏗️ Architecture

The server runs the active Whisper model in a dedicated subprocess. The main
FastAPI process communicates with that worker through local queues. When you
switch models via `PUT /models/active`, the old worker is stopped and a new
worker is started with the requested model, allowing the operating system to
reclaim model memory cleanly.

Same battle-tested idea as one-process-per-model serving, minus the orchestration
ceremony for a local dictation box.

The server is intended for localhost, LAN, or private-network use such as
Tailscale. Set `PHONOS_AUTH_TOKEN` before exposing it beyond localhost.

───

## 🚀 Quick start

### Server

The “server” can be another machine on your LAN/Tailscale network, or just a
Docker container running locally on the same Mac. For local-only use, set the
Mac app Server URL to `http://localhost:8765`.

```bash
git clone https://github.com/jb381/phonos && cd phonos/apps/server
cp .env.example .env          # optional: set PHONOS_AUTH_TOKEN
docker compose up -d          # boom, transcription server on :8765
```

Or run the published server image directly:

```bash
docker run -d \
  --name phonos-server \
  -p 8765:8765 \
  -e PHONOS_AUTH_TOKEN=your-secret-token \
  -v phonos_models:/root/.cache/huggingface \
  ghcr.io/jb381/phonos-server:latest
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
./dev-run.sh                  # fast dev loop: build, quit old app, launch new app
./build.sh                    # creates Phonos.dmg and Phonos.app
open Phonos.dmg               # then drag to Applications
```

For day-to-day macOS development, prefer `./dev-run.sh`. It builds a debug app
bundle at `.build/dev/Phonos.app`, ejects any mounted `Phonos` DMG volumes,
quits the currently running app, and opens the freshly built one. It avoids the
installer DMG loop entirely.

Releases are triggered by `git tag vX.Y.Z && git push --tags`. CI builds,
ad-hoc signs, and publishes a DMG automatically.

> **No Apple Developer account yet = ad-hoc signing.** Gatekeeper may complain on
> first launch — right-click the app and choose **Open**, or go to System Settings
> → Privacy & Security and click **Open Anyway**. Accessibility permission may
> need to be re-granted after ad-hoc rebuilds.
>
> To silence Gatekeeper from the terminal, `sudo` may be needed because the app
> lives in `/Applications`:
> ```bash
> sudo xattr -dr com.apple.quarantine /Applications/Phonos.app
> ```
> The grown-up version of this is Developer ID signing + notarization. It is on
> the roadmap.
>
> macOS does not allow scripts to grant Microphone or Accessibility permissions.
> The practical development fix is stable signing: set `PHONOS_CODESIGN_IDENTITY`
> or install/use an Apple Development identity so the first manual grant sticks
> across rebuilds. Ad-hoc signing changes the app's code requirement often enough
> that macOS may ask for permissions again.

───

## ✨ Features

- 🎙️ Menu-bar status item with recording/transcribing/paste state
- ⌨️ Global hotkey (Control-Space by default, customizable)
- 🎮 Hold-to-record and toggle recording modes
- 📋 Direct auto-paste into the previously active application
- 🧯 Clipboard fallback when Accessibility permission is not granted
- 🛠️ First-run setup for permissions and server connection
- 🔄 Model selector with live switching from the server
- 📜 Recent transcript history in the menu bar
- 🔐 Auth token stored in macOS Keychain

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
PHONOS_TRANSCRIBE_TIMEOUT_SECONDS=600
PHONOS_MAX_UPLOAD_MB=100
```

Docker Compose binds to `127.0.0.1` by default. For remote access, set `PHONOS_BIND=0.0.0.0` and `PHONOS_AUTH_TOKEN`.

───

## 🛡️ Privacy and security

- Audio is recorded by the macOS app and uploaded only to the configured Phonos server.
- The server does not require internet access after model files are downloaded and cached.
- Set `PHONOS_AUTH_TOKEN` before binding the server to a LAN or private network interface.
- The macOS auth token is stored in Keychain.
- Temporary client recording files are removed after each transcription flow completes.
- Recent transcript history is session-only in the current app.
- Server logs include request metadata and transcript text for debugging; run the server only where those logs are acceptable.

## ⚠️ Current limitations

- Official macOS builds are ad-hoc signed and not notarized yet, so Gatekeeper may require manual approval on first launch.
- Phonos is intended for localhost, LAN, or private networks such as Tailscale. Do not expose the server directly to the public internet.
- Clipboard restoration is best-effort for complex clipboard contents, though normal text clipboard restore is supported.
- Keychain integration tests are manual because unsigned test binaries can trigger macOS permission prompts.
- Persistent transcript history is not implemented; history is intentionally session-only for now.

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

Start with `small.en` for CPU usage. Try `turbo` or `distil-large-v3` if you
need higher quality or multilingual transcription. Use `large-v3` only when the
server has enough CPU/GPU capacity and memory.

───

## 📄 License

MIT — do whatever, just keep the Greek in the README. Preferably the murder one.

───

<div align="center">

*made with ☕, 🎧, a mild obsession with terminal aesthetics, and a name that apparently means murder*

</div>
