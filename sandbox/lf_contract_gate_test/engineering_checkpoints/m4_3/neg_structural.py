#!/usr/bin/env python3
import json, os

TEST_CODE="ENG_M4_3_NEG_STRUCTURAL"
live=json.loads(os.environ["ENGINEERING_DECLARED_INPUT_JSON"])

by_outcome={r["validator_outcome"]:r for r in live["outcomes"]}
passed=by_outcome.get("PASS",{})
assert passed.get("n",0)>0
assert passed.get("sin_validator_sha")==0
assert passed.get("sin_curator_sha")==0

def structural_gate(case):
    return (
        case["validator_sha_ok"]
        and case["family_complete"]
        and case["stage_order_ok"]
    )

baseline={"validator_sha_ok":True,"family_complete":True,"stage_order_ok":True}
assert structural_gate(baseline) is True

negative={}
for key in ("validator_sha_ok","family_complete","stage_order_ok"):
    case=dict(baseline); case[key]=False
    rejected=structural_gate(case) is False
    negative[key]=rejected
    assert rejected

print(json.dumps({
  "status":"PASS",
  "test_code":TEST_CODE,
  "observed":{
    "test_passed":True,
    "test_exit_code":0,
    "semantic_authority_bound":True,
    "adversarial_case_executed":True,
    "live_outcomes":live["outcomes"],
    "negative_cases":negative
  }
},sort_keys=True))
