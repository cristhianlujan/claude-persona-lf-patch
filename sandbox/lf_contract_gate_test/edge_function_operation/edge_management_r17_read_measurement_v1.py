"""R17 non-effect Management API read measurement for M10.5 CP2.

Measures GET only. It never deploys, writes SQL, mints R17 events or claims
the R17 authorization gate has passed. Durable artifacts are non-sensitive.
"""
from __future__ import annotations
import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from edge_management_credential_canary_v1 import (
    TARGET_SLUG, CanaryBlocked, read_existing_function,
)

READ_TIMEOUT_MS = 20_000  # Existing canary GET timeout; this is NOT a deployment limit.
SAMPLE_COUNT = 5
ARTIFACT_PATH = Path("r17_edge_management_read_diagnostic.json")


def collect(read: Callable[[], dict], clock: Callable[[], float] = time.perf_counter) -> dict:
    samples: list[float] = []
    versions: list[int] = []
    for _ in range(SAMPLE_COUNT):
        start = clock()
        reply = read()
        elapsed = (clock() - start) * 1000
        if (reply.get("result") != "EDGE_MANAGEMENT_READ_PASS"
            or reply.get("method") != "GET"
            or reply.get("target") != TARGET_SLUG
            or reply.get("deployed") is not False
            or reply.get("r17_authorized") is not False
            or reply.get("cp2_runs_started") != 0):
            raise CanaryBlocked("R17_READ_RECEIPT_NOT_CANONICAL")
        samples.append(round(elapsed, 3))
        versions.append(reply["version"])
    if len(set(versions)) != 1:
        raise CanaryBlocked("R17_READ_VERSION_DRIFT")
    sorted_ms = sorted(samples)
    p90_index = (9 * SAMPLE_COUNT + 9) // 10 - 1  # Nearest-rank p90.
    result = {
        "schema": "LF_EDGE_R17_READ_MEASUREMENT_V1",
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "github_run_id": os.getenv("GITHUB_RUN_ID", "LOCAL_TEST"),
        "github_commit": os.getenv("GITHUB_SHA", "LOCAL_TEST"),
        "operation_code": "DEPLOY_SUPABASE_EDGE_FUNCTION_LF",
        "target": TARGET_SLUG,
        "target_version": versions[0],
        "method": "GET",
        "samples_ms": samples,
        "sample_count": SAMPLE_COUNT,
        "p50_ms": round(statistics.median(samples), 3),
        "p90_ms": sorted_ms[p90_index],
        "max_ms": sorted_ms[-1],
        "read_timeout_ms": READ_TIMEOUT_MS,
        "read_within_timeout": sorted_ms[-1] <= READ_TIMEOUT_MS,
        "read_transport": "PASS" if sorted_ms[-1] <= READ_TIMEOUT_MS else "FAIL",
        "runtime_deploy_timing": "NOT_MEASURED",
        "r17_event": "NOT_ACCREDITED",
        "rollback_drill": "NOT_EXECUTED",
        "idempotency": "NOT_EXECUTED",
        "human_authorization": "NOT_ACCREDITED",
        "operation_effect": "NOT_EXECUTED",
        "r17_verdict": "INCOMPLETE_NOT_AUTHORIZED",
        "deploy_executed": False,
        "cp2_runs_started": 0,
    }
    return result


def main() -> int:
    try:
        token = os.getenv("SUPABASE_ACCESS_TOKEN", "")
        result = collect(lambda: read_existing_function(token))
        if result["read_transport"] != "PASS":
            exit_code = 2
        else:
            exit_code = 0
    except CanaryBlocked as exc:
        result = {
            "schema": "LF_EDGE_R17_READ_MEASUREMENT_V1",
            "operation_code": "DEPLOY_SUPABASE_EDGE_FUNCTION_LF",
            "read_transport": "BLOCKED",
            "failure_code": str(exc),
            "r17_verdict": "INCOMPLETE_NOT_AUTHORIZED",
            "deploy_executed": False,
            "cp2_runs_started": 0,
        }
        exit_code = 2
    ARTIFACT_PATH.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
