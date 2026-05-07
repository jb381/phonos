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
    from tests.utils import generate_silent_wav

    return generate_silent_wav(duration_seconds=1.0, sample_rate=16000)
