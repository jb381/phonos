import logging
import multiprocessing as mp
import os
import signal
import threading

from phonos_server.config import Settings

logger = logging.getLogger(__name__)

REQUEST_TIMEOUT = 600


def _worker_run(
    model_name: str,
    device: str,
    compute_type: str,
    cmd_queue: mp.Queue,
    result_queue: mp.Queue,
):
    """Entry point for the model worker subprocess."""
    os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)

    from faster_whisper import WhisperModel

    logger.info("Worker loading model: %s", model_name)
    model = WhisperModel(model_name, device=device, compute_type=compute_type)
    result_queue.put({"type": "ready", "model": model_name})

    while True:
        msg = cmd_queue.get()
        action = msg.get("action")

        if action == "transcribe":
            audio_path = msg["audio_path"]
            vad_filter = msg.get("vad_filter", True)
            try:
                segments, info = model.transcribe(audio_path, vad_filter=vad_filter)
                text = " ".join(seg.text.strip() for seg in segments)
                result_queue.put(
                    {
                        "type": "result",
                        "text": text,
                        "language": info.language,
                        "duration_seconds": round(info.duration, 2),
                    }
                )
            except Exception as exc:
                result_queue.put({"type": "error", "message": str(exc)})

        elif action == "quit":
            break

    del model


class ModelManager:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._lock = threading.Lock()
        self._model_name: str = ""
        self._process: mp.Process | None = None
        self._cmd_queue: mp.Queue | None = None
        self._result_queue: mp.Queue | None = None

    @property
    def active_model(self) -> str:
        return self._model_name

    def load(self, model_name: str):
        with self._lock:
            self._stop_worker()
            self._model_name = model_name
            self._start_worker(model_name)

    def _start_worker(self, model_name: str):
        ctx = mp.get_context("spawn")
        self._cmd_queue = ctx.Queue()
        self._result_queue = ctx.Queue()
        self._process = ctx.Process(
            target=_worker_run,
            args=(
                model_name,
                self.settings.device,
                self.settings.compute_type,
                self._cmd_queue,
                self._result_queue,
            ),
        )
        self._process.start()
        msg = self._result_queue.get(timeout=REQUEST_TIMEOUT)
        if msg.get("type") != "ready":
            self._stop_worker()
            raise RuntimeError(f"Worker failed to load model: {msg}")

    def _stop_worker(self):
        if self._process is None:
            return
        try:
            self._cmd_queue.put({"action": "quit"})
            self._process.join(timeout=10)
        except Exception:
            pass
        if self._process.is_alive():
            self._process.kill()
            self._process.join(timeout=5)
        self._process = None
        self._cmd_queue = None
        self._result_queue = None

    def shutdown(self):
        with self._lock:
            self._stop_worker()
            self._model_name = ""

    def transcribe(self, audio_path: str, **kwargs):
        with self._lock:
            if self._process is None or not self._process.is_alive():
                raise RuntimeError("No model loaded")
            self._cmd_queue.put(
                {
                    "action": "transcribe",
                    "audio_path": audio_path,
                    "vad_filter": self.settings.vad_filter,
                    **kwargs,
                }
            )
            msg = self._result_queue.get(timeout=REQUEST_TIMEOUT)
            if msg.get("type") == "error":
                raise RuntimeError(msg.get("message", "Transcription failed"))
            return {
                "text": msg["text"],
                "model": self._model_name,
                "language": msg.get("language", ""),
                "duration_seconds": msg.get("duration_seconds", 0),
            }
