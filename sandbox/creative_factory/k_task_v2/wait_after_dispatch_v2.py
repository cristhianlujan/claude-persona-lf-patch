"""SALY: wait for a dispatched, asynchronously observable image.

Production entrypoint needs a real readback callback. It cannot poll inside
a synchronous image_gen call. Clock and sleep are injected for deterministic tests.
"""
from __future__ import annotations

import time
from typing import Callable, Any


def wait_after_dispatch(
    readback: Callable[[], dict[str, Any]],
    expire: Callable[[], dict[str, Any]],
    *,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
    interval_seconds: int = 30,
    minimum_seconds: int = 180,
) -> dict[str, Any]:
    if interval_seconds != 30 or minimum_seconds != 180:
        raise ValueError("SALY_WAIT_POLICY_INVALID")
    start = monotonic()
    trace = []
    for n in range(7):  # time 0, 30, 60, 90, 120, 150, 180
        when = start + 30 * n
        delta = when - monotonic()
        if delta > 0:
            sleep(delta)
        row = readback()
        if not isinstance(row, dict) or row.get("status") not in (
            "READY", "PENDING", "FAILED"
        ):
            return {"status": "READBACK_INVALID", "checks": trace, "count": n + 1}
        status = row["status"]
        elapsed = 30 * n
        trace.append({"elapsed_seconds": elapsed, "status": status})
        if status in ("FAILED", "ERROR"):
            return {"status": status, "readback": row, "checks": trace,
                    "count": n + 1, "elapsed_seconds": elapsed}
        if status == "READY":
            return {
                "status": "READY",
                "first_observed_ready_seconds": elapsed,
                "checks": trace,
                "count": n + 1,
                "elapsed_seconds": elapsed,
                "next_step": "11",
            }
    result = expire()
    if not isinstance(result, dict) or result.get("status") != "EXPIRED_CLOSED":
        return {
            "status": "EXPIRY_NOT_CONFIRMED",
            "expire_readback": result,
            "checks": trace,
            "count": 7,
        }
    return {
        "status": "ESPERA_AGOTADA",
        "run_state": result.get("state"),
        "run_expired": True,
        "checks": trace,
        "count": 7,
        "elapsed_seconds": 180,
    }
