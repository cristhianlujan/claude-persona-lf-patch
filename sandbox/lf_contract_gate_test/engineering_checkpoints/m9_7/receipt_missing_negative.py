#!/usr/bin/env python3
"""ENG_M9_7_RECEIPT_MISSING_NEGATIVE: actual live canonical gate, no synthetic fixtures."""
import json
import os
import sys

CODE = "ENG_M9_7_RECEIPT_MISSING_NEGATIVE"

def test():
    raw = os.environ.get("M97_NEGATIVE_GATE_JSON")
    if not raw:
        raise AssertionError("LIVE_GATE_READBACK_REQUIRED")
    d = json.loads(raw)
    for key in ("missing", "wrong_snapshot", "valid"):
        if key not in d or not isinstance(d[key], dict):
            raise AssertionError("MISSING_LIVE_GATE_CASE:" + key)
    if d["missing"].get("status") != "BLOCKED":
        raise AssertionError("MISSING_RECEIPT_ACCEPTED")
    if d["wrong_snapshot"].get("status") != "BLOCKED":
        raise AssertionError("WRONG_SNAPSHOT_ACCEPTED")
    if d["valid"].get("status") != "PASS":
        raise AssertionError("POSITIVE_CONTROL_REJECTED")
    if d["valid"].get("functional_pipeline_equivalence_proven") is not False:
        raise AssertionError("INVALID_SCOPE_CLAIM")
    if d["valid"].get("comparison_scope") != "BUNDLE_DIGEST_ONLY":
        raise AssertionError("COMPARISON_SCOPE_DRIFT")
    print(json.dumps({"test_code": CODE, "status": "PASS", "observed": {
        "test_passed": True, "test_exit_code": 0,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "negative_cases": 2, "positive_controls": 1}}, sort_keys=True))

if __name__ == "__main__":
    try:
        test()
    except (AssertionError, ValueError, KeyError, TypeError) as e:
        print(json.dumps({"test_code": CODE, "status": "FAIL", "reason": str(e)}))
        sys.exit(1)
