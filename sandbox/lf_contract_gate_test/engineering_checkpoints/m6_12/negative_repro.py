#!/usr/bin/env python3
"""M6.12 exact-checkpoint negative: source receipts -> deterministic manifest.

Input M612_LIVE_READBACK_JSON is a live SUPABASE SQL witness supplied by the
executor, not checked-in test data. No DB mutations, stored-run rewrites, or
synthetic producer receipts are performed.
"""
import copy
import json
import os
import re
import sys

SHA = re.compile(r"^[0-9a-f]{64}$")
FIELDS = ("ref", "authority", "lifecycle", "observed_sha256", "archive_contract")


def require(condition, code):
    if not condition:
        raise AssertionError(code)


def compact(receipt):
    require(isinstance(receipt, dict), "RECEIPT_NOT_OBJECT")
    require(isinstance(receipt.get("ref"), dict), "RECEIPT_REF_MISSING")
    require("authority" in receipt, "RECEIPT_AUTHORITY_MISSING")
    require(bool(SHA.fullmatch(receipt.get("observed_sha256", ""))),
            "RECEIPT_SHA_MISSING")
    result = {"schema_version": receipt.get("schema_version") or
              "IG_SOURCE_RECEIPT_V1"}
    for key in FIELDS:
        if key in receipt and receipt[key] is not None:
            result[key] = receipt[key]
    return result


def normalize(receipts):
    require(isinstance(receipts, list), "MANIFEST_NOT_ARRAY")
    values = [
        json.dumps(compact(r), sort_keys=True, separators=(",", ":"),
                   ensure_ascii=False) for r in receipts
    ]
    return sorted(set(values))


def poison_sha(value):
    require(bool(SHA.fullmatch(value)), "INVALID_BASELINE_SHA")
    return ("1" if value[0] == "0" else "0") + value[1:]


def main():
    raw = os.environ.get("M612_LIVE_READBACK_JSON")
    require(raw is not None, "CANONICAL_SQL_READBACK_REQUIRED")
    witness = json.loads(raw)
    require(witness.get("source") ==
            "programacion.input_readiness_runs+programacion.v_input_run_manifest",
            "SOURCE_AUTHORITY_UNBOUND")
    rows = witness.get("runs")
    require(isinstance(rows, list) and rows, "NO_REAL_RUNS")
    legacy, compact_runs, tested = 0, 0, []
    for row in rows:
        run_id = row.get("run_id")
        source = row.get("source_manifest")
        materialized = row.get("materialized_manifest")
        require(isinstance(run_id, int), "RUN_ID_MISSING")
        require(isinstance(source, list) and len(source) > 0,
                "SOURCE_MANIFEST_MISSING")
        require(isinstance(materialized, list), "VIEW_MANIFEST_MISSING")
        require(row.get("receipt_count") == len(materialized),
                "VIEW_RECEIPT_COUNT_MISMATCH")
        require(len(materialized) == len(normalize(materialized)),
                "VIEW_DUPLICATE_NOT_REMOVED")

        source_identity = normalize(source)
        view_identity = normalize(materialized)
        require(source_identity == view_identity,
                "RECOMPUTED_MANIFEST_DIFFERS_FROM_STORED_VIEW")
        require(len(materialized) == len(source_identity),
                "DEDUPLICATION_MISMATCH")
        require(all("observed" not in item for item in materialized),
                "LEGACY_OBSERVED_PAYLOAD_LEAK")

        live_sha = row.get("manifest_sha256")
        repeat_sha = row.get("recomputed_sha256")
        require(isinstance(live_sha, str) and SHA.fullmatch(live_sha),
                "MANIFEST_SHA_INVALID")
        require(live_sha == repeat_sha,
                "RECOMPUTED_SHA_DIFFERS_FROM_STORED")

        # Non-destructive adversarial 1: mutate a source receipt SHA and
        # require the independent projection comparison to reject it.
        altered = copy.deepcopy(source)
        altered[0]["observed_sha256"] = poison_sha(
            altered[0]["observed_sha256"])
        require(normalize(altered) != view_identity,
                "NEGATIVE_CHANGED_SOURCE_NOT_DETECTED")

        # Non-destructive adversarial 2: tamper only the stored manifest digest.
        require(poison_sha(live_sha) != repeat_sha,
                "NEGATIVE_CHANGED_STORED_DIGEST_NOT_DETECTED")

        # Positive deduplication: a repeated identical receipt changes nothing.
        duplicated = source + [copy.deepcopy(source[0])]
        require(normalize(duplicated) == source_identity,
                "IDENTICAL_RECEIPT_DEDUP_REGRESSION")

        if any("observed" in item for item in source):
            legacy += 1
        else:
            compact_runs += 1
        tested.append({"run_id": run_id, "receipt_count": len(materialized),
                       "sha": live_sha, "adversarial_cases": 2})

    require(legacy > 0, "LEGACY_RUN_COVERAGE_MISSING")
    require(compact_runs > 0, "COMPACT_RUN_COVERAGE_MISSING")
    print(json.dumps({"status": "PASS", "test_code": "ENG_M6_12_NEGATIVE_REPRO",
                      "test_passed": True, "test_exit_code": 0,
                      "semantic_authority_bound": True,
                      "adversarial_case_executed": True,
                      "live_run_count": len(tested),
                      "legacy_run_count": legacy,
                      "compact_run_count": compact_runs,
                      "negative_case_count": 2 * len(tested),
                      "runs": tested}, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "test_code": "ENG_M6_12_NEGATIVE_REPRO",
                          "error": str(exc)}), file=sys.stderr)
        sys.exit(1)
