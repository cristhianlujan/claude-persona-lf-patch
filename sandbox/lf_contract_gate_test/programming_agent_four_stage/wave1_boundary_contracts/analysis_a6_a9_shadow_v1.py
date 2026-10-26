"""Opt-in A6/A9 shadow adapter. Returns the original response separately.

No caller or active route is installed by this module. The observer has no
authority to admit, block, dispatch, persist, or replace the active response.
Only a fixed trusted worker is launched; JSON input is sealed before dispatch.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import math
from pathlib import Path
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
MAX_INPUT_BYTES = 262144
MAX_OUTPUT_BYTES = 32768
_CAPACITY = threading.BoundedSemaphore(2)


def _report(state, **facts):
    return {"schema_version": "A6_A9_SHADOW_OBSERVATION_V1", "state": state,
            "advisory_only": True, "route_effect_allowed": False,
            "planning_allowed": False, "execution_allowed": False,
            "operational_admission": False, "persistence_allowed": False, **facts}


class Observation:
    """Advisory telemetry; waiting is separate from receiving the response."""
    def __init__(self, initial=None):
        self._event = threading.Event()
        self._value = initial
        if initial is not None:
            self._event.set()

    def _finish(self, value):
        self._value = value
        self._event.set()

    def read(self):
        if not self._event.is_set():
            return _report("PENDING")
        # Isolate consumers from modifying the saved observation.
        return json.loads(json.dumps(self._value, allow_nan=False))

    def wait(self, seconds=2.0):
        if type(seconds) not in (int, float) or not math.isfinite(seconds) or not 0 <= seconds <= 10:
            raise ValueError("OBSERVER_WAIT_LIMIT_INVALID")
        self._event.wait(seconds)
        return self.read()


@dataclass(frozen=True)
class ShadowDispatch:
    active_response: object
    observation: Observation


def _monitor(observation, sealed, deadline, lease):
    proc = None
    try:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            observation._finish(_report("TIMEOUT"))
            return
        proc = subprocess.Popen(
            [sys.executable, "-I", "-B", str(HERE / "analysis_a6_a9_shadow_v1.py"), "--worker"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
            close_fds=True, start_new_session=True,
        )
        try:
            raw, _ = proc.communicate(sealed, timeout=max(0.001, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            observation._finish(_report("TIMEOUT"))
            return
        if proc.returncode != 0:
            observation._finish(_report("ERROR", error_code="WORKER_EXIT_NONZERO"))
            return
        if len(raw) > MAX_OUTPUT_BYTES:
            observation._finish(_report("ERROR", error_code="WORKER_OUTPUT_LIMIT"))
            return
        summary = json.loads(raw)
        if (not isinstance(summary, dict)
                or set(summary) != {"schema_version", "preview_status", "issue_count", "issues", "ready_scope_ids"}
                or summary["schema_version"] != "A6_A9_SHADOW_WORKER_RESULT_V1"
                or summary["preview_status"] not in ("CANDIDATE_ASSEMBLED", "RETURN_TO_ANALYSIS")
                or type(summary["issue_count"]) is not int or summary["issue_count"] < 0
                or not isinstance(summary["issues"], list) or len(summary["issues"]) > 16
                or not isinstance(summary["ready_scope_ids"], list)
                or not all(isinstance(x, str) for x in summary["ready_scope_ids"])
                or len(summary["ready_scope_ids"]) > 64):
            observation._finish(_report("ERROR", error_code="WORKER_RESULT_INVALID"))
            return
        observation._finish(_report("OBSERVED", **{k: v for k, v in summary.items() if k != "schema_version"}))
    except Exception:
        observation._finish(_report("ERROR", error_code="SHADOW_OBSERVER_FAILED"))
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate()
        lease.release()


def shadow_after_response_v1(active_response, draft, a6_output, expected_a6_sha256,
                             *, enabled=False, timeout_seconds=1.0):
    """Seal a small JSON packet and start an advisory process asynchronously.

    No active caller is invoked, retried or caught here. Its result is already
    supplied. The returned active_response is the exact original object/bytes.
    Startup and bounded input serialization take time; this is not zero latency.
    This process separation is fault isolation for trusted code, not a security
    sandbox or proof of live runtime admission.
    """
    if enabled is False:
        return ShadowDispatch(active_response, Observation(_report("DISABLED")))
    if enabled is not True:
        return ShadowDispatch(active_response, Observation(_report("INPUT_REJECTED", error_code="SHADOW_ENABLE_INVALID")))
    if type(timeout_seconds) not in (int, float) or not math.isfinite(timeout_seconds) or not 0.05 <= timeout_seconds <= 5:
        return ShadowDispatch(active_response, Observation(_report("INPUT_REJECTED", error_code="SHADOW_TIMEOUT_INVALID")))
    lease = _CAPACITY
    if not lease.acquire(blocking=False):
        return ShadowDispatch(active_response, Observation(_report("SKIPPED_CAPACITY")))
    try:
        packet = {"draft": draft, "a6_output": a6_output, "expected_a6_sha256": expected_a6_sha256}
        sealed = json.dumps(packet, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode()
        if len(sealed) > MAX_INPUT_BYTES:
            raise ValueError("INPUT_LIMIT")
    except Exception:
        lease.release()
        return ShadowDispatch(active_response, Observation(_report("INPUT_REJECTED", error_code="SHADOW_INPUT_INVALID_OR_TOO_LARGE")))
    observation = Observation()
    try:
        thread = threading.Thread(target=_monitor, args=(observation, sealed, time.monotonic() + timeout_seconds, lease), daemon=True)
        thread.start()
    except Exception:
        lease.release()
        observation._finish(_report("ERROR", error_code="SHADOW_START_FAILED"))
    return ShadowDispatch(active_response, observation)


def _worker():
    # No inherited credentials and no bytecode writes. Trusted fixed evaluator.
    import resource
    resource.setrlimit(resource.RLIMIT_CPU, (2, 2))
    resource.setrlimit(resource.RLIMIT_AS, (268435456, 268435456))
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        return 2
    packet = json.loads(raw)
    if not isinstance(packet, dict) or set(packet) != {"draft", "a6_output", "expected_a6_sha256"}:
        return 2
    sys.path.insert(0, str(HERE))
    from analysis_a6_a9_preview_v1 import assemble_a6_a9_preview_v1
    result = assemble_a6_a9_preview_v1(packet["draft"], packet["a6_output"], packet["expected_a6_sha256"])
    if not all(result.get(k) is False for k in ("planning_allowed", "execution_allowed", "operational_admission", "persistence_allowed")):
        return 3
    issues = result["issues"]
    summary = {"schema_version": "A6_A9_SHADOW_WORKER_RESULT_V1",
               "preview_status": result["status"], "issue_count": len(issues),
               "issues": [{"path": str(i.get("path", ""))[:256], "code": str(i.get("code", ""))[:128]} for i in issues[:16]],
               "ready_scope_ids": result.get("ready_scope_ids", [])[:64]}
    payload = json.dumps(summary, ensure_ascii=True, allow_nan=False).encode()
    if len(payload) > MAX_OUTPUT_BYTES:
        return 2
    sys.stdout.buffer.write(payload)
    return 0


if __name__ == "__main__":
    if sys.argv[1:] != ["--worker"]:
        raise SystemExit(2)
    try:
        raise SystemExit(_worker())
    except Exception:
        raise SystemExit(2)
