import contextlib
import logging
import multiprocessing as mp
import os
import queue
import signal
import threading
import time

from phonos_server.config import Settings

logger = logging.getLogger(__name__)


def _worker_run(
    model_name: str,
    device: str,
    compute_type: str,
    cmd_queue: mp.Queue,
    result_queue: mp.Queue,
):
    """Entry point for the model worker subprocess."""
    logging.basicConfig(level=logging.INFO)
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
        self._status: str = "loading"
        self._last_error: str = ""
        self._last_load_seconds: float = 0
        self._started_at = time.time()
        self._transcription_count = 0
        self._last_processing_seconds: float = 0
        self._request_count = 0
        self._process: mp.Process | None = None
        self._cmd_queue: mp.Queue | None = None
        self._result_queue: mp.Queue | None = None

    @property
    def active_model(self) -> str:
        return self._model_name

    @property
    def status(self) -> str:
        if self._status == "loaded" and not self.worker_alive:
            return "error"
        return self._status

    @property
    def last_error(self) -> str:
        return self._last_error

    @property
    def last_load_seconds(self) -> float:
        return self._last_load_seconds

    @property
    def worker_alive(self) -> bool:
        return self._process is not None and self._process.is_alive()

    @property
    def uptime_seconds(self) -> float:
        return round(time.time() - self._started_at, 2)

    @property
    def transcription_count(self) -> int:
        return self._transcription_count

    @property
    def last_processing_seconds(self) -> float:
        return self._last_processing_seconds

    @property
    def request_count(self) -> int:
        return self._request_count

    def increment_request_count(self):
        with self._lock:
            self._request_count += 1

    def record_transcription(self, processing_seconds: float):
        self._transcription_count += 1
        self._last_processing_seconds = processing_seconds

    def load(self, model_name: str):
        with self._lock:
            if model_name == self._model_name and self._status == "loaded" and self.worker_alive:
                return
            self._stop_worker()
            self._status = "loading"
            self._last_error = ""
            start = time.time()
            try:
                self._start_worker(model_name)
            except Exception as exc:
                self._stop_worker()
                self._model_name = ""
                self._status = "error"
                self._last_error = str(exc)
                self._last_load_seconds = round(time.time() - start, 2)
                raise
            self._model_name = model_name
            self._status = "loaded"
            self._last_load_seconds = round(time.time() - start, 2)

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
        try:
            msg = self._result_queue.get(timeout=self.settings.model_load_timeout_seconds)
        except queue.Empty as exc:
            self._stop_worker()
            raise RuntimeError(f"Timed out loading model: {model_name}") from exc
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
        self._cleanup_queues()
        self._process = None
        self._cmd_queue = None
        self._result_queue = None

    def _cleanup_queues(self):
        for q in (self._cmd_queue, self._result_queue):
            if q is not None:
                try:
                    q.close()
                    q.join_thread()
                except Exception:
                    pass

    def shutdown(self):
        with self._lock:
            self._stop_worker()
            self._model_name = ""
            self._status = "loading"

    def transcribe(self, audio_path: str, **kwargs):
        with self._lock:
            if self._process is None or not self._process.is_alive():
                self._status = "error"
                self._last_error = "No model loaded"
                raise RuntimeError("No model loaded")
            timeout = self.settings.transcribe_timeout_seconds
            self._cmd_queue.put(
                {
                    "action": "transcribe",
                    "audio_path": audio_path,
                    "vad_filter": self.settings.vad_filter,
                    **kwargs,
                }
            )
            try:
                msg = self._result_queue.get(timeout=timeout)
            except queue.Empty as exc:
                self._last_error = f"Timed out transcribing audio after {timeout} seconds"
                # Drain any stale result so next call doesn't pick it up
                with contextlib.suppress(queue.Empty):
                    self._result_queue.get_nowait()
                raise TimeoutError(self._last_error) from exc
            if msg.get("type") == "error":
                raise RuntimeError(msg.get("message", "Transcription failed"))
            if "text" not in msg:
                raise RuntimeError(f"Unexpected worker response: {msg}")
            return {
                "text": msg["text"],
                "model": self._model_name,
                "language": msg.get("language", ""),
                "duration_seconds": msg.get("duration_seconds", 0),
            }
