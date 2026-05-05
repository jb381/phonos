import contextlib


class TestHealth:
    def test_health_ok(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "model" in data
        assert "worker_alive" in data
        assert "last_error" in data
        assert "last_load_seconds" in data
        assert "device" in data
        assert "compute_type" in data

    def test_health_returns_active_model(self, client):
        response = client.get("/health")
        data = response.json()
        assert data["model"] == "base.en"


class TestModels:
    def test_list_models(self, client):
        response = client.get("/models")
        assert response.status_code == 200
        data = response.json()
        assert "models" in data
        assert "active" in data
        assert "base.en" in data["models"]

    def test_get_active_model(self, client):
        response = client.get("/models/active")
        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "base.en"
        assert data["status"] == "loaded"


class TestModelSwitch:
    def test_set_active_model_valid(self, client_with_auth, auth_headers):
        response = client_with_auth.put(
            "/models/active",
            json={"model": "tiny.en"},
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["model"] == "tiny.en"
        assert data["status"] == "loaded"

    def test_set_active_model_invalid(self, client_with_auth, auth_headers):
        response = client_with_auth.put(
            "/models/active",
            json={"model": "nonexistent.en"},
            headers=auth_headers,
        )
        assert response.status_code == 400

    def test_set_active_model_no_body(self, client_with_auth, auth_headers):
        response = client_with_auth.put(
            "/models/active",
            headers=auth_headers,
        )
        assert response.status_code == 422

    def test_set_active_model_load_failure(self, client_with_auth, auth_headers, monkeypatch):
        import phonos_server.main as main_mod

        def fail_load(model):
            main_mod.manager._model_name = ""
            main_mod.manager._status = "error"
            main_mod.manager._last_error = f"Timed out loading model: {model}"
            raise RuntimeError(f"Timed out loading model: {model}")

        monkeypatch.setattr(main_mod.manager, "load", fail_load)

        response = client_with_auth.put(
            "/models/active",
            json={"model": "tiny.en"},
            headers=auth_headers,
        )

        assert response.status_code == 503
        health = client_with_auth.get("/health").json()
        assert health["status"] == "error"
        assert health["model"] == ""
        assert "tiny.en" in health["last_error"]


class TestModelManager:
    def test_load_does_not_publish_failed_model(self):
        from unittest.mock import patch

        from phonos_server.config import Settings
        from phonos_server.models import ModelManager

        manager = ModelManager(Settings())

        with (
            patch.object(ModelManager, "_start_worker", side_effect=RuntimeError("boom")),
            patch.object(ModelManager, "_stop_worker", return_value=None),
            contextlib.suppress(RuntimeError),
        ):
            manager.load("tiny.en")

        assert manager.active_model == ""
        assert manager.status == "error"
        assert manager.last_error == "boom"


class TestTranscribe:
    def test_transcribe_wav(self, client_with_auth, auth_headers, sample_wav):
        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert "text" in data
        assert data["model"] == "base.en"
        assert data["language"] == "en"
        assert "duration_seconds" in data
        assert "processing_seconds" in data

    def test_transcribe_empty_file(self, client_with_auth, auth_headers):
        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("empty.wav", b"", "audio/wav")},
            headers=auth_headers,
        )
        assert response.status_code == 400

    def test_transcribe_unsupported_format(self, client_with_auth, auth_headers, sample_wav):
        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.txt", sample_wav, "text/plain")},
            headers=auth_headers,
        )
        assert response.status_code == 400

    def test_transcribe_oversized_file(
        self, client_with_auth, auth_headers, sample_wav, monkeypatch
    ):
        from phonos_server.config import get_settings

        monkeypatch.setenv("PHONOS_MAX_UPLOAD_MB", "0")
        get_settings.cache_clear()

        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        get_settings.cache_clear()

        assert response.status_code == 413
        assert "upload limit" in response.json()["detail"]

    def test_transcribe_timeout(self, client_with_auth, auth_headers, sample_wav):
        import phonos_server.main as main_mod

        main_mod.manager.transcribe.side_effect = TimeoutError(
            "Timed out transcribing audio after 600 seconds"
        )

        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )

        assert response.status_code == 504
        assert "Timed out transcribing" in response.json()["detail"]


class TestAuth:
    def test_no_auth_when_not_configured(self, client):
        """Client without token configured should work without auth header."""
        response = client.get("/models")
        assert response.status_code == 200

    def test_auth_required_for_protected(self, client_with_auth):
        """With token configured, protected endpoints require auth."""
        response = client_with_auth.put(
            "/models/active",
            json={"model": "tiny.en"},
        )
        assert response.status_code == 401

    def test_invalid_token_rejected(self, client_with_auth):
        response = client_with_auth.put(
            "/models/active",
            json={"model": "tiny.en"},
            headers={"Authorization": "Bearer wrong-token"},
        )
        assert response.status_code == 401

    def test_health_is_unprotected(self, client_with_auth):
        """Health endpoint should not require auth."""
        response = client_with_auth.get("/health")
        assert response.status_code == 200
