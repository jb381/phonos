"""
End-to-end smoke test: Docker Compose server + real WAV -> transcribed text.

Requires Docker. Marked with ``@pytest.mark.e2e`` so it can be excluded
with ``-m "not e2e"`` and run selectively with ``-m e2e``.
"""

import io
import json
import os
import struct
import subprocess
import time
import urllib.error
import urllib.request

import pytest


@pytest.fixture(scope="module")
def docker_compose_up():
    """Start the Phonos Docker Compose server and wait for it to be healthy.

    Returns the base URL of the running server, e.g. ``http://localhost:8765``.
    Tears down the container(s) when the module's tests are done.
    """
    server_dir = os.path.join(os.path.dirname(__file__), "..")

    env = os.environ.copy()
    env["PHONOS_MODEL"] = "tiny.en"
    env["PHONOS_AUTH_TOKEN"] = ""

    subprocess.run(
        ["docker", "compose", "up", "-d", "--wait"],
        cwd=server_dir,
        env=env,
        check=True,
        capture_output=True,
        text=True,
        timeout=300,
    )

    base_url = "http://localhost:8765"
    deadline = time.monotonic() + 180
    last_error = None

    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{base_url}/health", timeout=10) as resp:
                data = json.loads(resp.read())
                if data.get("status") == "ok":
                    break
                last_error = data.get("last_error")
        except Exception as exc:
            last_error = str(exc)
        time.sleep(2)
    else:
        subprocess.run(
            ["docker", "compose", "down", "--volumes"],
            cwd=server_dir,
            check=False,
            capture_output=True,
            timeout=60,
        )
        pytest.fail(f"Server did not become healthy within 180 s. Last error: {last_error}")

    yield base_url

    subprocess.run(
        ["docker", "compose", "down", "--volumes"],
        cwd=server_dir,
        check=False,
        capture_output=True,
        timeout=60,
    )


@pytest.fixture(scope="module")
def sample_wav():
    """In-memory 16 kHz mono WAV with one second of silence (or close to it)."""
    buf = io.BytesIO()
    sample_rate = 16000
    num_samples = sample_rate  # 1 second

    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + num_samples * 2))
    buf.write(b"WAVE")
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))  # fmt chunk size
    buf.write(struct.pack("<HH", 1, 1))  # PCM, mono
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * 2))  # byte rate
    buf.write(struct.pack("<HH", 2, 16))  # block align, bits per sample
    buf.write(b"data")
    buf.write(struct.pack("<I", num_samples * 2))
    buf.write(b"\x00\x00" * num_samples)

    buf.seek(0)
    return buf


@pytest.mark.e2e
def test_transcribe_smoke(docker_compose_up, sample_wav):
    """POST a real WAV file to a real Docker server and verify transcription."""
    boundary = "----PhonosE2EBoundary"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="test.wav"\r\n'
        "Content-Type: audio/wav\r\n"
        "\r\n"
    ).encode("utf-8")
    body += sample_wav.read()
    body += f"\r\n--{boundary}--\r\n".encode("utf-8")

    req = urllib.request.Request(
        f"{docker_compose_up}/transcribe",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=120) as resp:
        assert resp.status == 200
        data = json.loads(resp.read())

    assert "text" in data, f"Missing 'text' in transcription response: {data}"
    assert isinstance(data["text"], str)
    assert "model" in data
    assert data["model"] == "tiny.en"


@pytest.mark.e2e
def test_health_returns_ok(docker_compose_up):
    """The health endpoint must report status 'ok' after model is loaded."""
    with urllib.request.urlopen(f"{docker_compose_up}/health", timeout=10) as resp:
        assert resp.status == 200
        data = json.loads(resp.read())

    assert data.get("status") == "ok"
    assert data.get("model") == "tiny.en"
    assert "worker_alive" in data
    assert "uptime_seconds" in data
    assert "device" in data
    assert "compute_type" in data


@pytest.mark.e2e
def test_models_list_includes_active(docker_compose_up):
    """The models endpoint should list the configured models and active model."""
    with urllib.request.urlopen(f"{docker_compose_up}/models", timeout=10) as resp:
        assert resp.status == 200
        data = json.loads(resp.read())

    assert "models" in data
    assert "tiny.en" in data["models"]
    assert data.get("active") == "tiny.en"
