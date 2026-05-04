import os
import tempfile
import time
import logging
from fastapi import UploadFile, HTTPException
from phonos_server.models import ModelManager
from phonos_server.config import Settings

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".flac", ".ogg", ".webm"}


def allowed_file(filename: str) -> bool:
    ext = os.path.splitext(filename)[1].lower()
    return ext in ALLOWED_EXTENSIONS


async def transcribe_audio(
    file: UploadFile,
    manager: ModelManager,
    settings: Settings,
) -> dict:
    if not file.filename or not allowed_file(file.filename):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type. Allowed: {', '.join(ALLOWED_EXTENSIONS)}",
        )

    content = await file.read()
    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Empty audio file")

    logger.info(
        "Received transcription request: filename=%s content_type=%s size_bytes=%d model=%s",
        file.filename,
        file.content_type,
        len(content),
        manager.active_model,
    )

    suffix = os.path.splitext(file.filename)[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(content)
        tmp_path = tmp.name

    try:
        start = time.time()
        result = manager.transcribe(tmp_path)
        result["processing_seconds"] = round(time.time() - start, 2)
        logger.info(
            "Transcription complete: model=%s language=%s duration_seconds=%s processing_seconds=%s text=%r",
            result.get("model"),
            result.get("language"),
            result.get("duration_seconds"),
            result.get("processing_seconds"),
            result.get("text", ""),
        )
        return result
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception("Transcription failed")
        raise HTTPException(status_code=500, detail="Transcription failed")
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
