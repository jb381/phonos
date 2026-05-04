import pytest
from unittest.mock import MagicMock, patch


@pytest.fixture
def mock_whisper():
    with patch("phonos_server.models.WhisperModel") as mock:
        instance = MagicMock()
        instance.transcribe.return_value = (
            [type("Seg", (), {"text": " hello world "})],
            type("Info", (), {"language": "en", "duration": 2.5}),
        )
        mock.return_value = instance
        yield mock


@pytest.fixture
def mock_model_manager(mock_whisper):
    from phonos_server.models import ModelManager
    from phonos_server.config import Settings

    settings = Settings(auth_token="test-token")
    manager = ModelManager(settings)
    manager.load(settings.model)
    return manager


@pytest.fixture
def client(mock_whisper):
    from fastapi.testclient import TestClient
    from phonos_server.main import app
    from phonos_server.config import get_settings
    from phonos_server.models import ModelManager

    settings = get_settings()
    mgr = ModelManager(settings)
    mgr.load(settings.model)

    import phonos_server.main as main_mod
    main_mod.manager = mgr

    return TestClient(app)


@pytest.fixture
def client_with_auth(mock_whisper, monkeypatch):
    from fastapi.testclient import TestClient
    from phonos_server.config import Settings, get_settings
    from phonos_server.models import ModelManager

    monkeypatch.setenv("PHONOS_AUTH_TOKEN", "test-token")
    get_settings.cache_clear()

    settings = Settings()
    import phonos_server.main as main_mod
    main_mod.manager = ModelManager(settings)
    main_mod.manager.load(settings.model)

    return TestClient(main_mod.app)


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer test-token"}


@pytest.fixture
def sample_wav():
    import struct
    import io

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
