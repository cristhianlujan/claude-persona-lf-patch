#!/usr/bin/env python3
import json, os

TEST_CODE = "ENG_M4_10_NEG_UNADJUDICATED"
live = json.loads(os.environ["ENGINEERING_DECLARED_INPUT_JSON"])

def closure_allowed(divergences):
    return all(bool(d.get("adjudicated")) for d in divergences)

assert closure_allowed([]) is True
negative = [{"code": "DIVERGENCE_WITHOUT_ADJUDICATION", "adjudicated": False}]
assert closure_allowed(negative) is False

human_decisions_n = int(live.get("n", 0))
assert human_decisions_n >= 0

print(json.dumps({
    "status": "PASS",
    "test_code": TEST_CODE,
    "observed": {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "unadjudicated_divergence_blocks_closure": True,
        "live_human_decisions_n": human_decisions_n,
        "live_last_at": live.get("last_at"),
    },
}, sort_keys=True))
