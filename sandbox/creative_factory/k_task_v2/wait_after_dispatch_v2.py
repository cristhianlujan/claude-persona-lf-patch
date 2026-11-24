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
            "READY", "PENDING", "FAILED", "ERROR"
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

# Concrete SQL signal contract. The executor must persist real output_evidence
# before a ready image is observable; a capture/prompt receipt is not READY.
RUN_READBACK_SQL = "SELECT saly.creative_run_image_readback_v2(%s,%s) AS result"
RUN_EXPIRE_SQL = "SELECT saly.creative_run_expire_v1(%s) AS result"


def wait_for_saly_run(
    execute_sql: Callable[[str, tuple[int, ...]], dict[str, Any]],
    run_id: int,
    item_id: int,
    **kwargs: Any,
) -> dict[str, Any]:
    """Wire 10b to the SQL readback and existing run-expiry RPC.

    execute_sql is an injected parameterized DB adapter whose return value
    is a single row {"result": {...}}. No adapter = no production polling.
    """
    if not isinstance(run_id, int) or run_id < 1:
        raise ValueError("SALY_INVALID_RUN_ID")
    if not isinstance(item_id, int) or item_id < 1:
        raise ValueError("SALY_INVALID_ITEM_ID")

    def call(sql: str, params: tuple[int, ...]) -> dict[str, Any]:
        row = execute_sql(sql, params)
        if not isinstance(row, dict) or not isinstance(row.get("result"), dict):
            return {"status": "ERROR", "reason": "SQL_READBACK_ROW_INVALID"}
        return row["result"]

    return wait_after_dispatch(
        lambda: call(RUN_READBACK_SQL, (run_id, item_id)),
        lambda: call(RUN_EXPIRE_SQL, (run_id,)),
        **kwargs,
    )
