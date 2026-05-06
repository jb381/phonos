"""
OpenAPI contract validation tests.

Verify that the *actual* server response shapes match the schemas defined in
``packages/protocol/openapi.yaml``.  These tests run against the FastAPI
``TestClient`` with the mock model manager, so they are fast and do not need a
real Whisper worker.
"""

from pathlib import Path

import yaml

PROTOCOL_DIR = Path(__file__).resolve().parents[3] / "packages" / "protocol"
SPEC_PATH = PROTOCOL_DIR / "openapi.yaml"


def _load_spec() -> dict:
    return yaml.safe_load(SPEC_PATH.read_text())


def _resolve_ref(spec: dict, ref: str) -> dict:
    """Follow a ``$ref`` URI like ``#/components/schemas/HealthResponse``."""
    parts = ref.removeprefix("#/").split("/")
    node = spec
    for part in parts:
        node = node[part]
    return node


def _get_response_schema(spec: dict, path: str, method: str, status: str = "200") -> dict:
    """Return the schema node for a given endpoint, method, and status code."""
    responses = spec["paths"][path][method]["responses"]
    content = responses[status]["content"]
    schema_ref = content["application/json"]["schema"]
    if "$ref" in schema_ref:
        return _resolve_ref(spec, schema_ref["$ref"])
    return schema_ref


# Load once at import time
SPEC = _load_spec()


def _keys_of(schema: dict) -> set:
    return set(schema.get("properties", {}).keys())


def _required_extra_keys(data: dict, schema: dict) -> tuple:
    expected = _keys_of(schema)
    actual = set(data.keys())
    return expected - actual, actual - expected


class TestHealthResponseContract:
    """Validate GET /health response against HealthResponse schema."""

    def test_health_response_keys(self, client):
        schema = _get_response_schema(SPEC, "/health", "get")
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()

        missing, _ = _required_extra_keys(data, schema)
        assert not missing, f"HealthResponse missing keys: {missing}"

    def test_health_status_is_valid_enum(self, client):
        schema = _get_response_schema(SPEC, "/health", "get")
        response = client.get("/health")
        data = response.json()

        allowed = schema["properties"]["status"].get("enum", [])
        assert "status" in data
        assert data["status"] in allowed, f"status '{data['status']}' not in {allowed}"

    def test_health_required_fields_have_correct_types(self, client):
        response = client.get("/health")
        data = response.json()

        assert isinstance(data.get("status"), str)
        assert isinstance(data.get("model"), str)
        assert isinstance(data.get("worker_alive"), bool)
        assert isinstance(data.get("uptime_seconds"), (int, float))
        assert isinstance(data.get("device"), str)
        assert isinstance(data.get("compute_type"), str)


class TestModelsResponseContract:
    """Validate GET /models and GET /models/active against their schemas."""

    def test_models_response_keys(self, client):
        schema = _get_response_schema(SPEC, "/models", "get")
        response = client.get("/models")
        assert response.status_code == 200
        data = response.json()

        missing, _ = _required_extra_keys(data, schema)
        assert not missing, f"ModelsResponse missing keys: {missing}"

    def test_active_model_response_keys(self, client):
        schema = _get_response_schema(SPEC, "/models/active", "get")
        response = client.get("/models/active")
        assert response.status_code == 200
        data = response.json()

        missing, _ = _required_extra_keys(data, schema)
        assert not missing, f"ActiveModelResponse missing keys: {missing}"

    def test_active_model_status_is_valid_enum(self, client):
        schema = _get_response_schema(SPEC, "/models/active", "get")
        response = client.get("/models/active")
        data = response.json()

        allowed = schema["properties"]["status"].get("enum", [])
        assert data["status"] in allowed, f"status '{data['status']}' not in {allowed}"


class TestTranscriptionResponseContract:
    """Validate POST /transcribe response against TranscriptionResponse schema."""

    def test_transcription_response_keys(self, client_with_auth, auth_headers, sample_wav):
        schema = _get_response_schema(SPEC, "/transcribe", "post")
        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()

        missing, _ = _required_extra_keys(data, schema)
        assert not missing, f"TranscriptionResponse missing keys: {missing}"

    def test_transcription_response_types(self, client_with_auth, auth_headers, sample_wav):
        response = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        data = response.json()

        assert isinstance(data.get("text"), str)
        assert isinstance(data.get("model"), str)
        if data.get("language") is not None:
            assert isinstance(data["language"], str)
        assert isinstance(data.get("duration_seconds"), (int, float))
        assert isinstance(data.get("processing_seconds"), (int, float))

        assert len(data["text"]) > 0, "Transcription text should be non-empty"


class TestErrorResponseContract:
    """Validate that error responses conform to the ErrorResponse schema."""

    def test_error_response_has_detail_or_error(self, client_with_auth):
        resp = client_with_auth.put(
            "/models/active",
            json={"model": "nonexistent.en"},
            headers={"Authorization": "Bearer test-token"},
        )
        assert resp.status_code == 400
        data = resp.json()
        assert "detail" in data or "error" in data, f"Error response missing detail/error: {data}"
        assert isinstance(data.get("detail", data.get("error")), str)

    def test_413_response_has_detail(self, client_with_auth, auth_headers, sample_wav, monkeypatch):
        from phonos_server.config import get_settings

        monkeypatch.setenv("PHONOS_MAX_UPLOAD_MB", "0")
        get_settings.cache_clear()

        resp = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        assert resp.status_code == 413
        data = resp.json()
        assert "detail" in data

    def test_504_response_has_detail(self, client_with_auth, auth_headers, sample_wav):
        import phonos_server.main as main_mod

        main_mod.manager.transcribe.side_effect = TimeoutError("Timed out after 600s")

        resp = client_with_auth.post(
            "/transcribe",
            files={"file": ("test.wav", sample_wav, "audio/wav")},
            headers=auth_headers,
        )
        assert resp.status_code == 504
        data = resp.json()
        assert "detail" in data
