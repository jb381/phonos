import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel

from phonos_server.auth import require_auth
from phonos_server.config import Settings, get_settings
from phonos_server.models import ModelManager
from phonos_server.transcription import transcribe_audio

logging.basicConfig(level=logging.INFO)


class SetModelRequest(BaseModel):
    model: str


manager: ModelManager | None = None
_transcribe_semaphore = asyncio.Semaphore(1)


def _require_manager() -> ModelManager:
    if manager is None:
        raise HTTPException(status_code=503, detail="Model manager is not initialized")
    return manager


@asynccontextmanager
async def lifespan(app: FastAPI):
    global manager
    settings = get_settings()
    manager = ModelManager(settings)
    manager.load(settings.model)
    yield
    manager.shutdown()


app = FastAPI(title="Phonos", version="0.1.0", lifespan=lifespan)


@app.middleware("http")
async def count_requests(request, call_next):
    if manager is not None:
        manager.increment_request_count()
    return await call_next(request)


@app.get("/health")
def health():
    active_manager = _require_manager()
    settings = get_settings()
    return {
        "status": "ok" if active_manager.status == "loaded" else active_manager.status,
        "model": active_manager.active_model,
        "worker_alive": active_manager.worker_alive,
        "last_error": active_manager.last_error,
        "last_load_seconds": active_manager.last_load_seconds,
        "uptime_seconds": active_manager.uptime_seconds,
        "request_count": active_manager.request_count,
        "transcription_count": active_manager.transcription_count,
        "last_processing_seconds": active_manager.last_processing_seconds,
        "device": settings.device,
        "compute_type": settings.compute_type,
    }


@app.get("/models")
def list_models(settings: Settings = Depends(get_settings)):
    active_manager = _require_manager()
    return {
        "models": settings.model_list(),
        "active": active_manager.active_model,
    }


@app.get("/models/active")
def get_active_model():
    active_manager = _require_manager()
    return {
        "model": active_manager.active_model,
        "status": active_manager.status,
    }


@app.put("/models/active")
def set_active_model(
    body: SetModelRequest,
    _=Depends(require_auth),
    settings: Settings = Depends(get_settings),
):
    active_manager = _require_manager()
    if body.model not in settings.model_list():
        raise HTTPException(
            status_code=400,
            detail=f"Unknown model: {body.model}. Available: {settings.model_list()}",
        )
    try:
        active_manager.load(body.model)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    return {"model": active_manager.active_model, "status": active_manager.status}


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    _=Depends(require_auth),
    settings: Settings = Depends(get_settings),
):
    active_manager = _require_manager()
    async with _transcribe_semaphore:
        return await transcribe_audio(file, active_manager, settings)
