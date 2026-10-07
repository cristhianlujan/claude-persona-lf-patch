#!/usr/bin/env python3
import copy
import json
import sys

TEST_CODE = "ENG_M5_5_NEGATIVE_ZERO_SHA"

def emit(status, observed):
    payload = {"status": status, "test_code": TEST_CODE, "observed": observed}
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(0 if status == "PASS" else 1)

if len(sys.argv) != 2:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": True,
        "adversarial_case_executed": False,
        "reason": "LIVE_NEGATIVE_EVIDENCE_JSON_REQUIRED",
    })

try:
    payload = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": True,
        "adversarial_case_executed": False,
        "reason": "LIVE_NEGATIVE_EVIDENCE_JSON_INVALID",
        "detail": str(exc),
    })

required = {
    "curator_zero_count",
    "guard_trigger_bound",
    "zero_sha_insert_rejected",
    "mismatch_sha_insert_rejected",
    "rollback_confirmed",
}
missing = sorted(k for k in required if k not in payload)
if missing:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": True,
        "adversarial_case_executed": False,
        "reason": "LIVE_NEGATIVE_EVIDENCE_FIELDS_MISSING",
        "missing": missing,
    })

def violations(p):
    out = []
    if int(p.get("curator_zero_count", -1)) != 0:
        out.append("CANONICAL_ZERO_SHA_ROWS_PRESENT")
    if p.get("guard_trigger_bound") is not True:
        out.append("GUARD_TRIGGER_NOT_BOUND")
    if p.get("zero_sha_insert_rejected") is not True:
        out.append("ZERO_SHA_INSERT_NOT_REJECTED")
    if p.get("mismatch_sha_insert_rejected") is not True:
        out.append("MISMATCH_SHA_INSERT_NOT_REJECTED")
    if p.get("rollback_confirmed") is not True:
        out.append("NEGATIVE_CASE_NOT_ROLLED_BACK")
    return out

# Prove the test is sensitive to regression instead of merely echoing PASS.
mutated = copy.deepcopy(payload)
mutated["zero_sha_insert_rejected"] = False
if not violations(mutated):
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "reason": "ADVERSARIAL_MUTATION_NOT_DETECTED",
    })

bad = violations(payload)
if bad:
    emit("FAIL", {
        "test_passed": False,
        "test_exit_code": 1,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "canonical_exit_criterion": "0 inserts con SHA en ceros",
        "violations": bad,
    })

emit("PASS", {
    "test_passed": True,
    "test_exit_code": 0,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": "0 inserts con SHA en ceros",
    "curator_zero_count": 0,
    "guard_trigger_bound": True,
    "zero_sha_insert_rejected": True,
    "mismatch_sha_insert_rejected": True,
    "rollback_confirmed": True,
})
