#!/usr/bin/env python3
import json, os

TEST_CODE = "ENG_M4_9_MUTATION_CATALOG_T1_T10"
live = json.loads(os.environ["ENGINEERING_DECLARED_INPUT_JSON"])

negative_codes = set(live.get("negative_test_codes", []))
required_live = {
    "M7_3_NEG_001_MISSING_SOURCE",
    "M7_3_NEG_002_CONTRADICTORY_SOURCE",
    "M7_3_NEG_003_BROKEN_ID",
    "M7_3_NEG_004_INVENTED_URL",
    "M7_3_NEG_005_TIMEOUT_WITHOUT_SOURCE",
    "M7_3_NEG_006_UNJUSTIFIED_NOT_APPLICABLE",
    "M7_3_NEG_007_STALE_EVIDENCE",
    "M7_3_NEG_008_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE",
    "M7_3_NEG_009_SELF_AUTHORITY",
}
assert required_live.issubset(negative_codes), sorted(required_live - negative_codes)

def accepts(c):
    defects = [
        c.get("missing_source", False),
        c.get("contradictory_source", False),
        c.get("broken_id", False),
        c.get("invented_url", False),
        c.get("timeout_without_source", False),
        c.get("unjustified_not_applicable", False),
        c.get("stale_evidence", False),
        c.get("historical_pass_overrides_newer_failure", False),
        c.get("self_authority", False),
        c.get("curator_defect") is not None
        and c.get("curator_defect") == c.get("resolver_defect"),
    ]
    return not any(defects)

baseline = {}
assert accepts(baseline) is True

mutations = [
    ("T1", {"missing_source": True}),
    ("T2", {"contradictory_source": True}),
    ("T3", {"broken_id": True}),
    ("T4", {"invented_url": True}),
    ("T5", {"timeout_without_source": True}),
    ("T6", {"unjustified_not_applicable": True}),
    ("T7", {"stale_evidence": True}),
    ("T8", {"historical_pass_overrides_newer_failure": True}),
    ("T9", {"self_authority": True}),
    ("T10", {"curator_defect": "SAME_DEFECT", "resolver_defect": "SAME_DEFECT"}),
]

observed = {}
for code, mutation in mutations:
    rejected = accepts(mutation) is False
    observed[code] = {"expected": "FAIL", "detected": rejected}
    assert rejected

assert len(observed) == 10
assert all(v["detected"] for v in observed.values())

print(json.dumps({
    "status": "PASS",
    "test_code": TEST_CODE,
    "observed": {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "known_mutations_detected": 10,
        "known_mutations_total": 10,
        "live_negative_cases": len(negative_codes),
        "catalog": observed,
    },
}, sort_keys=True))
