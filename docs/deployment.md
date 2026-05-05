# Phonos Deployment Guide

How to deploy the Phonos server on your local network via Tailscale.

## Prerequisites

- A server/NAS/desktop running Docker
- [Tailscale](https://tailscale.com) installed on both server and Mac
- Docker and Docker Compose on the server

## Quick Deploy

### 1. Clone the repo on your server

```bash
git clone <your-repo-url> phonos
cd phonos/apps/server
```

### 2. Configure

```bash
cp .env.example .env
```

Edit `.env` with your preferences:
```env
PHONOS_PORT=8765
PHONOS_AUTH_TOKEN=your-secret-token
PHONOS_MODEL=base.en
PHONOS_MODELS=tiny.en,base.en,small.en,medium.en
PHONOS_DEVICE=cpu
PHONOS_COMPUTE_TYPE=int8
PHONOS_TRANSCRIBE_TIMEOUT_SECONDS=600
```

### 3. Start the server

```bash
docker compose up -d
```

First launch downloads the Whisper model (may take a minute).

### 4. Verify

```bash
curl http://localhost:8765/health
# {"status":"ok","model":"base.en","device":"cpu","compute_type":"int8"}
```

## Tailscale Configuration

### Option A: Use Tailscale hostname (recommended)

1. Ensure both devices are on the same Tailscale tailnet.
2. Find your server's Tailscale name (e.g., `my-server`).
3. On the Mac client, set Server URL to:
   ```
   http://my-server:8765
   ```

### Option B: Use Tailscale IP

```bash
# On the server, find the Tailscale IP
tailscale ip -4
# e.g., 100.64.0.5
```

On Mac client, set Server URL to:
```
http://100.64.0.5:8765
```

### Option C: Direct LAN (if on same local network)

Use the server's LAN IP:
```
http://192.168.1.100:8765
```

## Token Authentication

Set a shared token in both `.env` (server) and the Mac app settings:

```env
# Server .env
PHONOS_AUTH_TOKEN=your-secret-token
```

In the Mac app Settings → Auth Token, enter the same value.

Without a token, the server is open to anyone on the network. Even with Tailscale, a token is recommended for defense-in-depth.

## Firewall

The server binds to `0.0.0.0:8765` inside Docker, mapped to host port `8765`.

For security:
- Use Tailscale as the only network path.
- If exposing on LAN, restrict with firewall rules.
- Always set a strong `PHONOS_AUTH_TOKEN`.

### UFW example (if needed)

```bash
# Allow only from Tailscale IP range
sudo ufw allow from 100.64.0.0/10 to any port 8765
```

## Model Recommendations (CPU)

| Model      | Speed (real-time) | Accuracy | RAM Usage |
|------------|-------------------|----------|-----------|
| `tiny.en`  | ~10x              | Good     | ~1 GB     |
| `base.en`  | ~5x               | Better   | ~1 GB     |
| `small.en` | ~2x               | Great    | ~2 GB     |
| `medium.en`| ~0.5x             | Best     | ~5 GB     |

- **`tiny.en`**: Fastest, good for quick dictation.
- **`base.en`** (default): Good balance of speed and accuracy.
- **`small.en`**: Best accuracy for a CPU-only setup.
- **`medium.en`**: Slow on CPU, use only if you have a powerful server.

All models use `int8` quantization by default for CPU efficiency.

## Model Cache

Models are downloaded once and cached in a Docker volume:
```
phonos_models -> /root/.cache/huggingface
```

To clear the model cache:
```bash
docker compose down -v
docker compose up -d
```

## Running Without Docker

```bash
cd apps/server
pip install -e ".[dev]"
uvicorn phonos_server.main:app --host 0.0.0.0 --port 8765
```

Install ffmpeg separately (required by faster-whisper):
```bash
# macOS
brew install ffmpeg

# Debian/Ubuntu
sudo apt install ffmpeg
```

## Systemd Service (optional)

```ini
# /etc/systemd/system/phonos.service
[Unit]
Description=Phonos Whisper Transcription Server
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/opt/phonos/apps/server
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now phonos
```

## Troubleshooting

### Server won't start
```bash
docker compose logs phonos
```

### Model download fails
Check internet connectivity. Models are cached in the Docker volume.

### Slow transcription on CPU
- Use a smaller model (`tiny.en` or `base.en`).
- Ensure `PHONOS_COMPUTE_TYPE=int8`.
- Consider a GPU-enabled server if available.
- Check VAD impact: set `PHONOS_VAD_FILTER=false` to see if VAD adds latency.
- If large models time out, raise `PHONOS_TRANSCRIBE_TIMEOUT_SECONDS` or switch to a smaller model.

### Connection refused from Mac client
- Verify Tailscale is running on both devices.
- Check server IP/hostname is correct in Mac app.
- Test connectivity: `curl http://<server>:8765/health` from Mac.

### Auth errors
- Ensure `PHONOS_AUTH_TOKEN` matches on both server and client.
- If auth is empty on server, no token check occurs.
