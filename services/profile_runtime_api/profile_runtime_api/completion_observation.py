"""Optional bounded notification after durable job completion. No result access."""
from __future__ import annotations

import logging
import threading
from typing import Any, Callable

_LOG = logging.getLogger(__name__)


class CompletionObservation:
    """At most two daemon callbacks per app; no queue, retries or job mutation.

    Callbacks receive a fresh metadata projection, never result/payload/store.
    A wedged callback holds its slot until exit; subsequent work is skipped.
    Threads are fault isolation for trusted code, not a security sandbox.
    """
    def __init__(self, callback: Callable[[dict[str, Any]], None] | None = None):
        self._callback = callback
        self._slots = threading.BoundedSemaphore(2)
        self._closed = threading.Event()

    def close(self) -> None:
        self._closed.set()

    def submit(self, job_id: str, meta: dict[str, Any]) -> str:
        if self._callback is None or self._closed.is_set():
            return "DISABLED"
        if not self._slots.acquire(blocking=False):
            return "SKIPPED_CAPACITY"
        try:
            # Fixed scalar projection: no arbitrary serialization on active path.
            profiles = meta.get("profiles")
            notice = {"job_id": job_id, "kind": meta.get("kind"),
                      "request_id": meta.get("request_id"),
                      "request_sha256": meta.get("request_sha256"),
                      "profiles": tuple(profiles) if isinstance(profiles, list) and len(profiles) == 1 else ()}
            values = (notice["job_id"], notice["kind"], notice["request_id"], notice["request_sha256"], *notice["profiles"])
            if any(not isinstance(x, str) or len(x) > 256 for x in values):
                self._slots.release()
                return "INPUT_REJECTED"
            thread = threading.Thread(target=self._run, args=(notice,), daemon=True,
                                      name="lf-completion-observation")
            thread.start()
            return "DISPATCHED"
        except Exception:
            self._slots.release()
            _LOG.warning("COMPLETION_OBSERVATION_START_FAILED")
            return "ERROR"

    def _run(self, notice: dict[str, Any]) -> None:
        try:
            if not self._closed.is_set():
                self._callback(notice)
        except Exception:
            # Do not leak exception messages, credentials or context payloads.
            _LOG.warning("COMPLETION_OBSERVATION_FAILED")
        finally:
            self._slots.release()
