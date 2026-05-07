import contextlib
import logging
import os
import tempfile
import time

from fastapi import HTTPException, UploadFile

from phonos_server.config import Settings
from phonos_server.models import ModelManager

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".flac", ".ogg", ".webm"}
UPLOAD_CHUNK_SIZE = 1024 * 1024


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

    max_upload_bytes = settings.max_upload_mb * 1024 * 1024
    suffix = os.path.splitext(file.filename)[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp_path = tmp.name
        size_bytes = 0
        while chunk := await file.read(UPLOAD_CHUNK_SIZE):
            size_bytes += len(chunk)
            if size_bytes > max_upload_bytes:
                with contextlib.suppress(OSError):
                    os.unlink(tmp_path)
                raise HTTPException(
                    status_code=413,
                    detail=f"Audio file exceeds {settings.max_upload_mb} MB upload limit",
                )
            tmp.write(chunk)

    if size_bytes == 0:
        with contextlib.suppress(OSError):
            os.unlink(tmp_path)
        raise HTTPException(status_code=400, detail="Empty audio file")

    # Validate WAV magic bytes when the extension claims WAV
    if suffix == ".wav":
        with open(tmp_path, "rb") as f:
            header = f.read(12)
        if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            with contextlib.suppress(OSError):
                os.unlink(tmp_path)
            raise HTTPException(status_code=400, detail="Invalid WAV file header")

    logger.info(
        "Received transcription request: filename=%s content_type=%s size_bytes=%d model=%s",
        file.filename,
        file.content_type,
        size_bytes,
        manager.active_model,
    )

    try:
        start = time.time()
        result = manager.transcribe(tmp_path)
        result["processing_seconds"] = round(time.time() - start, 2)
        manager.record_transcription(result["processing_seconds"])
        logger.info(
            "Transcription complete: model=%s language=%s duration_seconds=%s "
            "processing_seconds=%s text=%r",
            result.get("model"),
            result.get("language"),
            result.get("duration_seconds"),
            result.get("processing_seconds"),
            result.get("text", ""),
        )
        return result
    except TimeoutError as e:
        raise HTTPException(status_code=504, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except Exception:
        logger.exception("Transcription failed")
        raise HTTPException(status_code=500, detail="Transcription failed") from None
    finally:
        with contextlib.suppress(OSError):
            os.unlink(tmp_path)
