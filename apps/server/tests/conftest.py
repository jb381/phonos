from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def mock_model_manager():
    """Provides a ModelManager with mocked subprocess worker.

    Patches _start_worker and _stop_worker so no real subprocess is spawned.
    Transcription returns canned results.
    """
    from phonos_server.config import Settings
    from phonos_server.models import ModelManager

    with (
        patch.object(ModelManager, "_start_worker", return_value=None),
        patch.object(ModelManager, "_stop_worker", return_value=None),
    ):
        settings = Settings(auth_token="test-token")
        manager = ModelManager(settings)
        manager._model_name = settings.model
        manager._status = "loaded"
        manager._last_load_seconds = 0.01
        manager._process = MagicMock()
        manager._process.is_alive.return_value = True

        manager.transcribe = MagicMock(
            return_value={
                "text": "hello world",
                "model": settings.model,
                "language": "en",
                "duration_seconds": 2.5,
            }
        )

        yield manager


@pytest.fixture
def client(mock_model_manager):
    from fastapi.testclient import TestClient

    import phonos_server.main as main_mod
    from phonos_server.config import get_settings
    from phonos_server.main import app

    get_settings.cache_clear()
    main_mod.manager = mock_model_manager
    return TestClient(app)


@pytest.fixture
def client_with_auth(mock_model_manager, monkeypatch):
    from fastapi.testclient import TestClient

    from phonos_server.config import get_settings

    monkeypatch.setenv("PHONOS_AUTH_TOKEN", "test-token")
    get_settings.cache_clear()

    import phonos_server.main as main_mod

    main_mod.manager = mock_model_manager
    return TestClient(main_mod.app)


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer test-token"}


@pytest.fixture
def sample_wav():
    import io
    import struct

    buf = io.BytesIO()
    sample_rate = 16000
    num_samples = 16000

    buf.write(b"RIFF")
    buf.write(struct.pack("<I", 36 + num_samples * 2))
    buf.write(b"WAVE")
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))
    buf.write(struct.pack("<HH", 1, 1))
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * 2))
    buf.write(struct.pack("<HH", 2, 16))
    buf.write(b"data")
    buf.write(struct.pack("<I", num_samples * 2))
    buf.write(b"\x00\x00" * num_samples)

    buf.seek(0)
    return buf
