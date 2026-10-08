#!/usr/bin/env python3
"""M8.6 negative parity: live three-screen readbacks and historical 13x47 corpus.

The runner consumes fresh Supabase authority readbacks in M86_PARITY_AUTHORITY_CASE_JSON.
Source observations are supplied by the governed executor, not hardcoded or inferred.
A negative (tampered manifest digest/parity flag) must be rejected.
"""
from __future__ import annotations
import copy
import hashlib
import json
import os
import re
import sys

TEST_CODE = "ENG_M8_6_NEGATIVE_PARITY"
SHA = re.compile(r"^[0-9a-f]{64}$")
FIELDS = (
    "statuses_equal", "open_equal", "unresolved_equal", "negative_equal",
    "tests_equal", "handles_equal", "counts_equal", "pins_equal"
)


def require(value: bool, reason: str) -> None:
    if not value:
        raise AssertionError(reason)


def canonical_sha(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    ).hexdigest()


def verify_fresh(row: dict) -> None:
    require(isinstance(row, dict), "FRESH_ROW_TYPE")
    require(isinstance(row.get("run_id"), int) and row["run_id"] > 0, "RUN_ID")
    require(isinstance(row.get("pantalla_id"), int) and row["pantalla_id"] > 0, "SCREEN_ID")
    require(row.get("source_ref") == f"supabase://programacion.input_readiness_runs/{row['run_id']}", "SOURCE_REF")
    require(row.get("current") is True and row.get("status") == "COMPLETED", "NOT_GENUINELY_FRESH")
    require(row.get("family_count") == 47 and row.get("validator_pass_count") == 47, "VALIDATOR_47_REQUIRED")
    for field in FIELDS:
        require(row.get(field) is True, "PARITY_MISMATCH_" + field)
    for field in ("manifest_sha", "recomputed_sha", "altered_sha"):
        require(isinstance(row.get(field), str) and SHA.fullmatch(row[field]) is not None, "SHA_FORMAT_"+field)
    require(row["manifest_sha"] == row["recomputed_sha"], "MANIFEST_CANONICAL_SHA_DRIFT")
    require(row["altered_sha"] != row["manifest_sha"], "ADVERSARIAL_SHA_NOT_DETECTED")


def verify_historical(row: dict) -> None:
    require(isinstance(row, dict), "HISTORIC_ROW_TYPE")
    require(isinstance(row.get("run_id"), int) and row["run_id"] > 0, "HISTORIC_RUN_ID")
    require(isinstance(row.get("pantalla_id"), int) and row["pantalla_id"] > 0, "HISTORIC_SCREEN")
    require(row.get("family_count") == 47, "HISTORIC_FAMILY_COUNT")
    families = row.get("families")
    require(isinstance(families, list) and len(families) == 47, "HISTORIC_47_RECORDS")
    codes = []
    for family in families:
        require(set(family) == {"family_code", "curator_sha256", "validator_sha256"}, "HISTORIC_FAMILY_SHAPE")
        require(isinstance(family["family_code"], str) and family["family_code"], "HISTORIC_FAMILY_CODE")
        require(isinstance(family["curator_sha256"], str) and SHA.fullmatch(family["curator_sha256"]) is not None, "HISTORIC_CURATOR_SHA")
        if family["validator_sha256"] is not None:
            require(isinstance(family["validator_sha256"], str) and SHA.fullmatch(family["validator_sha256"]) is not None, "HISTORIC_VALIDATOR_SHA")
        codes.append(family["family_code"])
    require(len(set(codes)) == 47 and codes == sorted(codes), "HISTORIC_FAMILY_UNIVERSE")
    digest = row.get("historical_digest")
    require(isinstance(digest, str) and SHA.fullmatch(digest) is not None, "HISTORIC_DIGEST_FORMAT")
    require(canonical_sha(families) == digest, "HISTORIC_DIGEST_MISMATCH")


def execute() -> dict:
    payload = json.loads(os.environ["M86_PARITY_AUTHORITY_CASE_JSON"])
    require(payload.get("schema_version") == "M86_SUPABASE_SOURCE_BOUND_PARITY_V1", "SOURCE_SCHEMA")
    fresh = payload.get("fresh")
    old = payload.get("historical")
    require(isinstance(fresh, list) and len(fresh) == 3, "FRESH_THREE_SCREENS_REQUIRED")
    require(isinstance(old, list) and len(old) == 13, "HISTORIC_THIRTEEN_REQUIRED")
    for row in fresh:
        verify_fresh(row)
    require(len({x["run_id"] for x in fresh}) == 3, "DUPLICATE_FRESH_RUNS")
    require(len({x["pantalla_id"] for x in fresh}) == 3, "DUPLICATE_FRESH_SCREENS")
    for row in old:
        verify_historical(row)
    require(len({x["run_id"] for x in old}) == 13, "DUPLICATE_HISTORIC_RUNS")
    require(len({x["pantalla_id"] for x in old}) == 13, "DUPLICATE_HISTORIC_SCREENS")
    require(all(x["run_id"] not in {r["run_id"] for r in fresh} for x in old), "HISTORY_AS_FRESH_FORBIDDEN")

    # Execute the adversarial branch of this independent verifier, do not
    # merely read a producer-supplied negative status claim.
    negative = copy.deepcopy(fresh[0])
    negative["statuses_equal"] = False
    rejected_parity = False
    try:
        verify_fresh(negative)
    except AssertionError:
        rejected_parity = True
    require(rejected_parity, "ADVERSARIAL_PARITY_FALSE_PASS")
    negative = copy.deepcopy(fresh[1])
    negative["manifest_sha"] = "0" * 64
    rejected_sha = False
    try:
        verify_fresh(negative)
    except AssertionError:
        rejected_sha = True
    require(rejected_sha, "ADVERSARIAL_SHA_FALSE_PASS")
    negative_history = copy.deepcopy(old[0])
    negative_history["families"][0]["curator_sha256"] = "1" * 64
    rejected_history = False
    try:
        verify_historical(negative_history)
    except AssertionError:
        rejected_history = True
    require(rejected_history, "ADVERSARIAL_HISTORY_FALSE_PASS")

    return {
        "schema_version": "ENGINEERING_M8_6_NEGATIVE_PARITY_RUN_V1",
        "test_code": TEST_CODE, "status": "PASS", "test_passed": True,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "fresh_screen_count": 3, "fresh_family_assertions": 141,
        "historical_screen_count": 13, "historical_family_assertions": 611,
        "manifest_parity_dimensions_per_screen": len(FIELDS),
        "negative_parity_rejected": True,
        "negative_sha_rejected": True,
        "negative_historical_tamper_rejected": True,
        "fresh_refs": [row["source_ref"] for row in fresh],
    }


if __name__ == "__main__":
    try:
        print(json.dumps(execute(), ensure_ascii=False, separators=(",", ":")))
        sys.exit(0)
    except Exception as exc:
        print(json.dumps({"test_code": TEST_CODE, "status": "FAIL", "error": str(exc)}))
        sys.exit(1)
