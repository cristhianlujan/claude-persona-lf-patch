#!/usr/bin/env python3
"""M6.12 live-bound negative proof verifier.

The executor executes a read-only canonical Supabase SQL probe that projects
input_readiness_runs.source_manifest and recomputes the manifest after changing
one source receipt SHA in a CTE (no persistent mutation). Only result booleans,
counts and digests are sent to the runner; no source payload leaves Supabase.
"""
import copy
import json
import os
import re
import sys


SHA = re.compile(r"^[0-9a-f]{64}$")
SOURCE = "programacion.input_readiness_runs+programacion.v_input_run_manifest"


def require(value, reason):
    if not value:
        raise AssertionError(reason)


def validate(row):
    require(isinstance(row.get("id"), int), "RUN_ID_MISSING")
    require(isinstance(row.get("receipt_count"), int)
            and row["receipt_count"] > 0, "RECEIPT_COUNT_INVALID")
    require(isinstance(row.get("stored_sha"), str)
            and SHA.fullmatch(row["stored_sha"]), "STORED_SHA_INVALID")
    require(row.get("baseline_reproduced") is True,
            "BASELINE_MANIFEST_REPRODUCTION_FAILED")
    require(row.get("source_mutation_detected") is True,
            "SOURCE_MUTATION_NOT_DETECTED")
    require(row.get("positive_and_negative_pass") is True,
            "CANONICAL_SQL_NEGATIVE_FAILED")
    require(row.get("leaked_payloads") == 0,
            "LEGACY_OBSERVED_PAYLOAD_LEAK")
    require(type(row.get("legacy_source")) is bool,
            "SOURCE_FORMAT_CLASSIFICATION_MISSING")


def main():
    raw = os.environ.get("M612_LIVE_NEGATIVE_RESULT_JSON")
    require(bool(raw), "LIVE_SQL_NEGATIVE_RESULT_REQUIRED")
    result = json.loads(raw)
    require(result.get("schema_version") == "M612_LIVE_NEGATIVE_SQL_V1",
            "SQL_PROBE_SCHEMA_MISMATCH")
    require(result.get("source") == SOURCE, "CANONICAL_SOURCE_UNBOUND")
    rows = result.get("runs")
    require(isinstance(rows, list) and len(rows) >= 2,
            "MULTI_RUN_READBACK_REQUIRED")
    require(len({x.get("id") for x in rows}) == len(rows),
            "DUPLICATE_RUN_EVIDENCE")
    for row in rows:
        validate(row)
    require(any(row["legacy_source"] for row in rows),
            "LEGACY_SOURCE_NOT_COVERED")
    require(any(not row["legacy_source"] for row in rows),
            "COMPACT_SOURCE_NOT_COVERED")

    # Runner-level negatives: rejecting tampered SQL result is mandatory.
    for changed_key, poison in (
        ("source_mutation_detected", False),
        ("stored_sha", "bad_sha"),
    ):
        hostile = copy.deepcopy(rows[0])
        hostile[changed_key] = poison
        try:
            validate(hostile)
        except AssertionError:
            pass
        else:
            raise AssertionError("RUNNER_ACCEPTED_HOSTILE_RESULT:" + changed_key)

    print(json.dumps({
        "status": "PASS",
        "test_code": "ENG_M6_12_NEGATIVE_REPRO",
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "sql_live_source_tamper_detected": True,
        "runner_hostile_result_cases": 2,
        "live_run_count": len(rows),
        "run_ids": [r["id"] for r in rows],
        "leaked_payloads": 0
    }, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"status": "FAIL",
                          "test_code": "ENG_M6_12_NEGATIVE_REPRO",
                          "error": str(exc)}), file=sys.stderr)
        sys.exit(1)
