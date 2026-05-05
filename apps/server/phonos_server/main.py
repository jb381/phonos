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
request_count = 0


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
    global request_count
    request_count += 1
    return await call_next(request)


@app.get("/health")
def health():
    return {
        "status": "ok" if manager.status == "loaded" else manager.status,
        "model": manager.active_model,
        "worker_alive": manager.worker_alive,
        "last_error": manager.last_error,
        "last_load_seconds": manager.last_load_seconds,
        "uptime_seconds": manager.uptime_seconds,
        "request_count": request_count,
        "transcription_count": manager.transcription_count,
        "last_processing_seconds": manager.last_processing_seconds,
        "device": get_settings().device,
        "compute_type": get_settings().compute_type,
    }


@app.get("/models")
def list_models(settings: Settings = Depends(get_settings)):
    return {
        "models": settings.model_list(),
        "active": manager.active_model,
    }


@app.get("/models/active")
def get_active_model():
    return {
        "model": manager.active_model,
        "status": manager.status,
    }


@app.put("/models/active")
def set_active_model(
    body: SetModelRequest,
    _=Depends(require_auth),
    settings: Settings = Depends(get_settings),
):
    if body.model not in settings.model_list():
        raise HTTPException(
            status_code=400,
            detail=f"Unknown model: {body.model}. Available: {settings.model_list()}",
        )
    try:
        manager.load(body.model)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    return {"model": manager.active_model, "status": manager.status}


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    _=Depends(require_auth),
    settings: Settings = Depends(get_settings),
):
    return await transcribe_audio(file, manager, settings)
