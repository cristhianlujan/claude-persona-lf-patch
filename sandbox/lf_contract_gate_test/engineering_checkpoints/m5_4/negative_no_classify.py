#!/usr/bin/env python3
import copy
import json
import sys

TEST_CODE = "ENG_M5_4_NEGATIVE_NO_CLASSIFY"
EXPECTED = {
    "programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)",
    "programacion.fn_input_governance_curator_rebind_v1(integer,text,text,bigint)",
    "programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text,boolean)",
    "programacion.fn_input_governance_recurate_source_stale_v1(integer,bigint,text)",
    "programacion.fn_input_governance_recurate_v2(integer,bigint,text)",
}


def violations(rows):
    found = []
    for row in rows:
        if row.get("calls_classify"):
            found.append({"fn": row.get("f"), "reason": "LEGACY_CLASSIFY_REFERENCE"})
        if row.get("calls_probe"):
            found.append({"fn": row.get("f"), "reason": "LEGACY_PROBE_REFERENCE"})
    return found


def emit(status, observed):
    payload = {"status": status, "test_code": TEST_CODE, "observed": observed}
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(0 if status == "PASS" else 1)


if len(sys.argv) != 2:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": False,
        "reason": "LIVE_FUNCTION_READBACK_JSON_REQUIRED",
    })

try:
    rows = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": False,
        "reason": "LIVE_FUNCTION_READBACK_JSON_INVALID", "detail": str(exc),
    })

if not isinstance(rows, list):
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": False,
        "reason": "LIVE_FUNCTION_READBACK_ARRAY_REQUIRED",
    })

seen = {row.get("f") for row in rows if isinstance(row, dict)}
missing = sorted(EXPECTED - seen)
if missing:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": False,
        "reason": "DECLARED_FUNCTIONS_MISSING", "missing": missing,
    })

# Adversarial sensitivity: the test itself must reject a reintroduced legacy reference.
mutated = copy.deepcopy(rows)
mutated[0]["calls_classify"] = True
if not violations(mutated):
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "reason": "ADVERSARIAL_MUTATION_NOT_DETECTED",
    })

bad = violations(rows)
if bad:
    emit("FAIL", {
        "test_passed": False, "test_exit_code": 1,
        "semantic_authority_bound": True, "adversarial_case_executed": True,
        "canonical_exit_criterion": "0 legacy classify_v1/v2 or probe_v1/v2/v3 references from declared Curator functions",
        "violations": bad,
    })

emit("PASS", {
    "test_passed": True,
    "test_exit_code": 0,
    "semantic_authority_bound": True,
    "adversarial_case_executed": True,
    "canonical_exit_criterion": "0 legacy classify_v1/v2 or probe_v1/v2/v3 references from declared Curator functions",
    "declared_function_count": len(EXPECTED),
    "legacy_reference_count": 0,
})
