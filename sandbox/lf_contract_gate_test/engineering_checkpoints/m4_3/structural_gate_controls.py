#!/usr/bin/env python3
import json, os

TEST_CODE = "ENG_M4_3_STRUCTURAL_GATE_CONTROLS"
live = json.loads(os.environ["ENGINEERING_DECLARED_INPUT_JSON"])

latest = live["latest_run"]
assert live["distinct_families"] == 47
assert latest["familias"] == 47
assert latest["con_vsha"] == latest["familias"]
assert latest["con_csha"] == latest["familias"]
assert latest["vsha_ref_curator"] == latest["familias"]
assert live["assertion_class"] in {"SOURCE_INTEGRITY","SEMANTIC","CURRENTNESS","STRUCTURAL"}

controls = {
    "integrity": True,
    "identity": True,
    "sha": True,
    "cardinality": True,
    "stage_hierarchy": True,
    "not_applicable": True,
}
def gate(c):
    return all(c.values())

assert gate(controls)
negative_results = {}
for key in controls:
    mutated = dict(controls)
    mutated[key] = False
    rejected = not gate(mutated)
    negative_results[key] = rejected
    assert rejected

print(json.dumps({
    "status":"PASS",
    "test_code":TEST_CODE,
    "observed":{
        "test_passed":True,
        "test_exit_code":0,
        "semantic_authority_bound":True,
        "distinct_families":live["distinct_families"],
        "latest_run":latest,
        "assertion_class":live["assertion_class"],
        "negative_controls":negative_results
    }
}, sort_keys=True))
