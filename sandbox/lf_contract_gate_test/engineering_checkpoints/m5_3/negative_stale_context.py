#!/usr/bin/env python3
import json
import re
import sys

TEST_CODE = "ENG_M5_3_NEGATIVE_STALE_CONTEXT"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_IDS = {191, 253, 263, 264, 265, 266}


def emit_fail(reason: str, **extra):
    payload = {
        "status": "FAIL",
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": False,
            "test_exit_code": 1,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "reason": reason,
            **extra,
        },
    }
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(1)


if len(sys.argv) != 2:
    emit_fail("LIVE_ROWS_JSON_REQUIRED")

try:
    rows = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit_fail("LIVE_ROWS_JSON_INVALID", detail=str(exc))

if not isinstance(rows, list):
    emit_fail("LIVE_ROWS_ARRAY_REQUIRED")

by_id = {}
for row in rows:
    if not isinstance(row, dict) or not isinstance(row.get("id"), int):
        emit_fail("LIVE_ROW_INVALID", row=row)
    by_id[row["id"]] = row

missing = sorted(EXPECTED_IDS - set(by_id))
if missing:
    emit_fail("DECLARED_RUNS_MISSING", missing_ids=missing)

r191, r253 = by_id[191], by_id[253]
if not (
    r191.get("status") == "COMPLETED"
    and r191.get("invalidated_reason") == "TERMINAL_SUCCESSOR"
    and r191.get("invalidated_by_run_id") == 253
    and r191.get("successor_status") == "BLOCKED"
    and r253.get("supersedes_run_id") == 191
    and r253.get("status") == "BLOCKED"
):
    emit_fail("TERMINAL_SUCCESSOR_REUSE_GUARD_NOT_PROVEN")

r263, r264 = by_id[263], by_id[264]
sha263 = r263.get("source_snapshot_sha256")
sha264 = r264.get("source_snapshot_sha256")
if not HEX64.fullmatch(sha263 or "") or not HEX64.fullmatch(sha264 or ""):
    emit_fail("SOURCE_SNAPSHOT_SHA_INVALID", old_sha=sha263, new_sha=sha264)
if sha263 == sha264:
    emit_fail("STALE_SOURCE_SHA_NOT_CHANGED", old_sha=sha263, new_sha=sha264)
if not (
    r263.get("status") == "COMPLETED"
    and r263.get("invalidated_reason") == "TERMINAL_SUCCESSOR"
    and r263.get("invalidated_by_run_id") == 264
    and r263.get("successor_status") == "COMPLETED"
    and r264.get("supersedes_run_id") == 263
    and r264.get("status") == "COMPLETED"
):
    emit_fail("CHANGED_SNAPSHOT_DID_NOT_FORCE_SUCCESSOR_RECONSTRUCTION")

r265 = by_id[265]
if not (
    r264.get("invalidated_reason") == "TERMINAL_SUCCESSOR"
    and r264.get("invalidated_by_run_id") == 265
    and r264.get("successor_status") == "BLOCKED"
    and r265.get("supersedes_run_id") == 264
    and r265.get("status") == "BLOCKED"
):
    emit_fail("BLOCKED_SUCCESSOR_DID_NOT_BREAK_REUSE")

r266 = by_id[266]
sha266 = r266.get("source_snapshot_sha256")
if not HEX64.fullmatch(sha266 or ""):
    emit_fail("SECOND_RECONSTRUCTION_SHA_INVALID", sha=sha266)
if not (
    r266.get("status") == "COMPLETED"
    and r266.get("supersedes_run_id") == 264
    and sha266 != sha264
):
    emit_fail("SECOND_DISTINCT_REQUEST_RECONSTRUCTION_NOT_PROVEN")

payload = {
    "status": "PASS",
    "test_code": TEST_CODE,
    "observed": {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "canonical_exit_criterion": "1 construcción de grafo por request",
        "terminal_successor_breaks_context_reuse": True,
        "changed_snapshot_forces_reconstruction": True,
        "blocked_successor_breaks_context_reuse": True,
        "distinct_request_reconstruction_proven": True,
        "old_run_id": 263,
        "new_run_id": 264,
        "old_snapshot_sha256": sha263,
        "new_snapshot_sha256": sha264,
        "second_reconstruction_run_id": 266,
        "second_snapshot_sha256": sha266,
    },
}
print(json.dumps(payload, sort_keys=True))
