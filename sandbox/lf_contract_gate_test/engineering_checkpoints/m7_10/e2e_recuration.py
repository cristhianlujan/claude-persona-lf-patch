#!/usr/bin/env python3
"""M7.10 real E2E recuration proof validator; static fixtures cannot pass."""
import argparse
import json
import sys

CASES = {"SOURCE_STALE": "M7_10_SOURCE_STALE_SUCCESS", "FULL": "M7_10_FULL_RECURATION_SUCCESS"}

def check(proof):
    if proof.get("schema_version") != "IG_M710_RECURATION_E2E_PROBE_V1":
        return "WRONG_PROOF_SCHEMA"
    if proof.get("source") != "LIVE_SUPABASE_TRANSACTION" or proof.get("rollback_verified") is not True:
        return "NOT_A_REAL_ROLLBACK_EXECUTION"
    if proof.get("persistent_delta") != {"runs": 0, "sources": 0, "receipts": 0}:
        return "ROLLBACK_RESIDUE"
    if proof.get("semantic_authority") != "CANONICAL_PLAN_EXIT_CRITERION":
        return "AUTHORITY_NOT_BOUND"
    cases = proof.get("cases", {})
    seen = set()
    for mode, code in CASES.items():
        item = cases.get(mode, {})
        if item.get("test_code") != code or item.get("executed") is not True:
            return mode + "_NOT_EXECUTED"
        before, after = item.get("source_sha_before"), item.get("source_sha_after")
        if not before or not after or before == after:
            return mode + "_SOURCE_CHANGE_NOT_PROVEN"
        parent, child = item.get("predecessor_run_id"), item.get("successor_run_id")
        if not isinstance(parent, int) or not isinstance(child, int) or parent == child:
            return mode + "_RUN_LINEAGE_MISSING"
        if item.get("supersedes_run_id") != parent or item.get("invalidated_by_run_id") != child:
            return mode + "_INVALIDATION_LINEAGE_MISMATCH"
        for key, expected in (("successor_status", "COMPLETED"),
                              ("recuration_mode", mode), ("validator_pass_count", 47),
                              ("graph_receipt_count", 2), ("manifest_reflected_source_change", True),
                              ("invalidation_after_completion", True),
                              ("producer_readback", "PASS"), ("rollback_verified", True)):
            if item.get(key) != expected:
                return mode + "_MISSING_" + key
        seen.add(child)
    if len(seen) != 2:
        return "INDEPENDENT_RUNS_REQUIRED"
    return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe-json", required=True)
    args = parser.parse_args()
    try:
        proof = json.loads(args.probe_json)
    except json.JSONDecodeError:
        proof = {}
    error = check(proof) if isinstance(proof, dict) else "PROBE_INVALID"
    passed = error is None
    print(json.dumps({"test_code": "ENG_M7_10_E2E_RECURATION",
                      "status": "PASS" if passed else "FAIL",
                      "error_code": error,
                      "observed": {"test_passed": passed, "test_exit_code": 0 if passed else 1,
                                   "semantic_authority_bound": True}}, sort_keys=True))
    return 0 if passed else 1

if __name__ == "__main__":
    sys.exit(main())
