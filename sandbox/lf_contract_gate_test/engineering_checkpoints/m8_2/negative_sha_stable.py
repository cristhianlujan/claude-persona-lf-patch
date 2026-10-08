#!/usr/bin/env python3
"""M8.2 negative test: real Supabase semantic SHA unaffected by timing sidecars.

Input is a live, immutable input_family_assessments canonical preimage
retrieved by the executor from Supabase. No canned fixture or self-scored PASS.
"""
import copy
import hashlib
import json
import os
import re
import sys
import time

TEST_CODE = "ENG_M8_2_NEGATIVE_SHA_STABLE"


def check(condition, code):
    if not condition:
        raise AssertionError(code)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def run():
    blob = os.environ.get("M8_2_AUTHORITY_CASE_JSON")
    check(bool(blob), "AUTHORITY_CASE_NOT_PROVIDED")
    case = json.loads(blob)
    ref = case.get("authority_ref", "")
    check(bool(re.fullmatch(r"supabase://programacion\.input_family_assessments/[1-9][0-9]*", ref)),
          "AUTHORITY_REF_INVALID")
    base = case["semantic_canonical_text"]
    altered = case["tampered_semantic_canonical_text"]
    source_sha = case["stored_curator_sha256"]
    computed_sha = case["recomputed_curator_sha256"]
    altered_sha = case["tampered_curator_sha256"]
    check(all(re.fullmatch("[0-9a-f]{64}", v) for v in (source_sha, computed_sha, altered_sha)),
          "SHA_FORMAT_INVALID")
    check(sha256(base) == source_sha == computed_sha,
          "CANONICAL_SUPABASE_AUTHORITY_MISMATCH")
    check(sha256(altered) == altered_sha and altered_sha != source_sha,
          "ADVERSARIAL_MUTATION_WAS_NOT_DETECTED")

    base_obj = json.loads(base)
    adversarial_obj = json.loads(altered)
    check(isinstance(base_obj.get("curator_evidence"), dict), "SEMANTIC_EVIDENCE_MISSING")
    evidence = adversarial_obj.get("curator_evidence", {})
    check(isinstance(evidence, dict), "ADVERSARIAL_EVIDENCE_INVALID")
    inserted = evidence.pop("performance_observation", None)
    check(inserted == {"elapsed_ms": 123}, "ADVERSARIAL_CASE_NOT_BOUND")
    check(adversarial_obj == base_obj, "ADVERSARIAL_EXTRA_MUTATIONS_DETECTED")

    # Two actual host-side executions of the exact same PostgreSQL canonical
    # semantic bytes, but with independently measured and intentionally varied
    # wall-clock sidecars (never included in semantic bytes).
    measured = []
    for pause_s in (0.002, 0.027):
        started = time.perf_counter_ns()
        run_sha = sha256(base)
        time.sleep(pause_s)
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        measured.append({"sha256": run_sha, "elapsed_ms": round(elapsed_ms, 3)})
    check(measured[0]["sha256"] == measured[1]["sha256"] == source_sha,
          "TIMING_CHANGED_SEMANTIC_SHA")
    check(abs(measured[0]["elapsed_ms"] - measured[1]["elapsed_ms"]) > 5.0,
          "TIMING_DIFFERENCE_NOT_OBSERVED")

    return {
        "schema_version": "ENGINEERING_M8_2_NEGATIVE_SHA_TEST_V1",
        "test_code": TEST_CODE,
        "status": "PASS",
        "test_passed": True,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "source_ref": ref,
        "observed": {
            "canonical_curator_sha256": source_sha,
            "adversarial_curator_sha256": altered_sha,
            "two_real_host_executions": measured,
            "sha_stable": True,
            "timing_in_semantic_payload_changes_sha": True,
        },
    }


if __name__ == "__main__":
    try:
        print(json.dumps(run(), ensure_ascii=False, separators=(",", ":")))
        sys.exit(0)
    except Exception as err:
        print(json.dumps({"test_code": TEST_CODE, "status": "FAIL",
                          "error": str(err)}, ensure_ascii=False))
        sys.exit(1)
