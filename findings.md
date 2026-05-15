# Phonos — Deep Code Review Findings

**Date:** May 12, 2026
**Scope:** All server (Python) and client (Swift) source files, tests, docs, config
**Lines reviewed:** ~6,000 across 41 files

---

## 🔴 Critical

### 1. Stale transcription result after timeout (models.py:183–229)

**File:** `apps/server/phonos_server/models.py`
**Lines:** 216 (timeout), 200–229 (transcribe method)

When `transcribe()` times out (`queue.Empty` at line 216), the worker process is still alive and will eventually complete the old command, placing the result in `self._result_queue`. The next call to `transcribe()` reads that **stale result** from the previous request immediately at line 216, returning the wrong transcription to the caller. This is cross-request data leakage.

**Fix:** On timeout, drain the stale result from the queue before sending a new command, or restart the worker process entirely. At minimum:
```python
except queue.Empty:
    self._last_error = f"Timed out after {current_timeout}s"
    # Drain any stale result that may arrive later
    try:
        stale = self._result_queue.get_nowait()
    except queue.Empty:
        pass
    raise ...
```

### 2. Worker lock held during blocking I/O (models.py:200–229)

`transcribe()` holds `self._lock` (a `threading.Lock`) for the entire duration of `self._result_queue.get(timeout=timeout)` — up to 600 seconds. This blocks ALL other operations that need the lock, including `load()` (model switching), `shutdown()`, and `health()` status. A slow transcription renders the entire server unresponsive.

**Fix:** Use a finer-grained lock or a condition variable so that status checks and health probes can proceed while a transcription is running.

### 3. Temp file leak on write failure (transcription.py:36–48)

`tempfile.NamedTemporaryFile(delete=False)` at line 36 means the file is NOT auto-deleted on context exit. If `tmp.write(chunk)` at line 48 raises `OSError` (disk full, permission error), the exception propagates out before the `try/finally` at lines 72–96 is reached. The temp file leaks permanently on disk.

**Fix:** Wrap the entire write phase (lines 36–68) in a try/finally that calls `os.unlink` if an exception occurs before the main try block.

### 4. Stale result in JSON-serialized model catalog (test level)

**File:** `apps/macos/Tests/ModelCatalogTests.swift`
**Line:** ~55–75

`ModelCatalog` tests compare against hardcoded JSON strings. If the server adds or removes models, these tests silently pass without catching the drift. No fixture machinery regenerates the test data.

---

## 🟡 High Priority

### 5. Auth is optional by default — zero-auth mode (auth.py:6)

`PHONOS_AUTH_TOKEN=""` means no authentication. Users deploying outside isolated LAN may not realize auth is off. `.env.example` defaults to empty. A startup log warning when auth is disabled would prevent accidental exposure.

### 6. No TLS anywhere (Dockerfile:21, docker-compose.yml:6)

Audio data and auth tokens (if configured) are transmitted in cleartext over HTTP. Client `Info.plist` has `NSAllowsArbitraryLoads = true`. Acceptable for Tailscale/LAN-only, but a hard dependency on network isolation.

### 7. No rate limiting on `/transcribe` (main.py)

Any authenticated (or unauthenticated) client can send unlimited transcription requests, keeping the server busy indefinitely. A per-IP or per-token rate limiter (FastAPI middleware or nginx) is absent.

### 8. Strong reference cycle in AudioRecorder tap closure (AudioRecorder.swift:81–88)

The `installTap` closure captures `self` (the `AudioRecorder` actor) strongly. Combined with `self.engine = engine` at line 100, this creates a cycle: `engine` → tap closure → `self` → `engine`. Broken when `stopRecording()` sets `engine = nil`, but if the app crashes during recording, the `AudioRecorder` leaks.

**Fix:** Use `[weak self]` in the tap closure, or set `self.engine = nil` in a `defer {}` block in `startRecording()`.

### 9. Fragile timing-based paste target activation (RecordingSession.swift:94–96)

250ms of `Task.sleep` before pasting is a heuristic. Under system load or rapid app switching, the paste goes to the wrong app. `reactivatePasteTarget` at lines 136–142 captures `bundleIdentifier` at recording start, which may be stale.

### 10. Manual transcription timeout leaves worker in inconsistent state (models.py:216–219)

When `_result_queue.get()` times out, the worker is still alive and may complete later. No worker restart is attempted. The `_last_error` is set but the worker isn't terminated — it continues processing the original request.

### 11. Double serialization bottleneck (main.py:21 + models.py:65)

`asyncio.Semaphore(1)` at the endpoint level AND `threading.Lock()` in `ModelManager` means only one transcription at a time. Limits throughput to ~1 request per processing interval. While intentional (Whisper memory), it should be documented as an architectural constraint.

### 12. Missing `PHONOS_BIND` in `.env.example` (config gap)

`docker-compose.yml` line 6 supports `PHONOS_BIND` (defaults to `0.0.0.0`) but it's not documented in `.env.example`. Users on shared machines may inadvertently bind to all interfaces.

### 13. Model load timeout not configurable (models.py:13)

`REQUEST_TIMEOUT = 600` is hardcoded. Unlike `transcribe_timeout_seconds` (env-configurable), this timeout for model loading is not adjustable. If a model download takes >600s, the server fails to start with no recourse.

### 14. No WAL mode in SQLite (db.py:84–89) — TileHarvester finding, but Phonos shares this if using SQLite

N/A — Phonos doesn't use SQLite. But the same principle applies to any state file: no concurrent access protection.

---

## 🟡 Medium Priority

### 15. Mock replaces real worker logic entirely (tests/conftest.py:28–35)

`manager.transcribe = MagicMock(...)` replaces the real queue-based transcribe with a canned response. The queue mechanism, timeout handling, worker crash/recovery, and race conditions in the worker are never tested.

### 16. Missing tests for:
- Concurrent requests (semaphore + lock interaction)
- Worker process crashes mid-transcription
- Model load failures (test at test_api.py:71 covers RuntimeError but not subprocess crashes)
- Network partition / server restart during transcription
- Oversized files at the exact boundary
- Timeout path in `transcribe()`

### 17. OpenAPI contract tests only check key presence (test_openapi_contract.py)

Most contract tests check only that expected keys exist in responses. Only `test_health_required_fields_have_correct_types` and `test_transcription_response_types` check actual value types.

### 18. NetworkScanner serial batch scanning (NetworkScanner.swift:107–130)

Scans 254 hosts in serial batches of 32. Total ~12s scan time. Could use a single `TaskGroup` with controlled concurrency.

### 19. New URLSession per ServerClient init (ServerClient.swift:77)

Each `ServerClient()` creates a new `URLSession`. No HTTP connection pooling across requests.

### 20. Empty device UID conflicts with "System Default" (AudioDeviceManager.swift:52)

If a device has no UID, it gets `""` as its ID. The "System Default" picker option also uses `""` (SettingsView.swift:54). Indistinguishable in the UI.

### 21. Inconsistent permission API (FirstRunView.swift vs AudioRecorder.swift)

`FirstRunView` uses deprecated `AVCaptureDevice.requestAccess(for: .audio)` while `AudioRecorder` uses modern `AVAudioApplication.requestRecordPermission`.

### 22. `DispatchSourceTimer` on main queue (MenuBarController.swift:57)

Line 363 uses `DispatchSource.makeTimerSource(queue: .main)` — unnecessarily low-level. `DispatchQueue.main.asyncAfter` or `Timer` would be simpler.

### 23. `handleResponse` returns Data unchanged (ServerClient.swift:96–109)

Returns the input `Data` parameter verbatim (or throws). Callers ignore the return value at line 190. Could be `throws -> Void`.

### 24. Debounced keychain write drops last keystroke (SettingsManager.swift:27–40)

300ms debounce means if the app crashes within 300ms of typing, the last token value is lost in the Keychain (though retained in memory).

### 25. `load()` blocks inside the lock for up to 600s (models.py:124–143)

`_start_worker` at line 160 does `self._result_queue.get(timeout=600)` while holding the lock. Blocks health checks and model listing.

### 26. Audio device switching failure silently ignored (AudioRecorder.swift:73–78)

`_ = audioDeviceClient.setDefaultInputDevice(selectedUID)` discards the `Bool` return value. If the device was unplugged, it silently fails.

### 27. CGEvent paste blocked by SIP (PasteEngine.swift:31–44)

Simulating Cmd+V via `CGEvent` can be blocked by macOS System Integrity Protection in secure text fields, password managers, and Terminal. `AXIsProcessTrusted()` at line 17 checks accessibility permission but isn't sufficient for all apps.

### 28. LaunchAtLoginManager throws without signing guidance (LaunchAtLoginManager.swift:7)

`SMAppService.mainApp.register()` throws if the app isn't signed or isn't in `/Applications`. The error is shown but with no hint about signing requirements.

---

## 🔵 Low Priority / Cosmetic

### 29. Mutable module-level global (main.py:20)

`manager: ModelManager | None = None` is mutated in `lifespan()` and tests. Fragile if lifespan runs twice.

### 30. Keychain service name hardcoded (KeychainStore.swift:7)

`private static let service = "dev.phonos.app"` — not configurable for different instances.

### 31. Generic 500 for unknown errors (transcription.py:91–93)

`except Exception: raise HTTPException(status_code=500, detail="Transcription failed") from None` swallows the traceback.

### 32. Redundant double decode in ServerClient (ServerClient.swift:190)

`handleResponse` return is discarded, then JSON decoded again.

---

## ✅ Looks Good

- Clean Swift actor usage on `AudioRecorder`, `RecordingSession`, `PasteEngine`
- Well-structured test separation (unit + e2e + contract)
- Comprehensive OpenAPI spec (5 endpoints, 6 schemas)
- Good documentation: architecture.md, deployment.md, roadmap.md
- Sensible default hotkey (Ctrl+Space, unlikely to conflict)
- Env var config via pydantic-settings is clean and documented in `.env.example`
- CI/CD pipeline with GitHub Actions (4 jobs)
- Semantic versioning with tags (v1.0.0–v1.4.1)
