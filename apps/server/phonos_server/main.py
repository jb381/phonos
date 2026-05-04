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


@asynccontextmanager
async def lifespan(app: FastAPI):
    global manager
    settings = get_settings()
    manager = ModelManager(settings)
    manager.load(settings.model)
    yield


app = FastAPI(title="Phonos", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health():
    return {
        "status": "ok" if manager.active_model else "loading",
        "model": manager.active_model,
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
        "status": "loaded" if manager.active_model else "loading",
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
    manager.load(body.model)
    return {"model": manager.active_model, "status": "loaded"}


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    _=Depends(require_auth),
    settings: Settings = Depends(get_settings),
):
    return await transcribe_audio(file, manager, settings)
