import threading
import logging
from faster_whisper import WhisperModel
from phonos_server.config import Settings

logger = logging.getLogger(__name__)


class ModelManager:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._lock = threading.Lock()
        self._model: WhisperModel | None = None
        self._model_name: str = ""

    @property
    def active_model(self) -> str:
        return self._model_name

    def load(self, model_name: str):
        with self._lock:
            if self._model is not None:
                del self._model
                self._model = None
            logger.info("Loading model: %s", model_name)
            self._model = WhisperModel(
                model_name,
                device=self.settings.device,
                compute_type=self.settings.compute_type,
            )
            self._model_name = model_name
            logger.info("Model loaded: %s", model_name)

    def transcribe(self, audio_path: str, **kwargs):
        with self._lock:
            if self._model is None:
                raise RuntimeError("No model loaded")
            segments, info = self._model.transcribe(
                audio_path,
                vad_filter=self.settings.vad_filter,
                **kwargs,
            )
            text = " ".join(seg.text.strip() for seg in segments)
            return {
                "text": text,
                "model": self._model_name,
                "language": info.language,
                "duration_seconds": round(info.duration, 2),
            }
