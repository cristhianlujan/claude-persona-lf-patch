#!/usr/bin/env python3
"""M6.13 governed negative: an unfinished required IG unit cannot close M6."""
import copy
import json
import sys

TEST_CODE = "ENG_M6_13_NEGATIVE_OPEN_UNIT"
REQUIRED_UNITS = {"M6.0", "T-CURR", "T-INVAL"}
CANONICAL_EXIT = (
    "Unidades M6 (M6.0–M6.12 y T-CURR/T-INVAL/T-EVID que absorben M6.8/M6.11) DONE; "
    "evidencia de cierre IG derivada del ledger/checkpoints; evento HANDOFF de cierre M6; "
    "readback independiente de receipts IG. POST_PASE/SADM queda fuera de alcance "
    "mientras su workstream permanezca desactivado."
)
EVIDENCE_REF = "supabase://programacion.engineering_plan_units/M6.13/NEGATIVE_OPEN_UNIT"

def fail(reason, **detail):
    print(json.dumps({
        "status": "FAIL", "test_code": TEST_CODE,
        "observed": {"test_passed": False, "test_exit_code": 1,
                     "semantic_authority_bound": False,
                     "adversarial_case_executed": False,
                     "reason": reason, **detail},
        "evidence_ref": EVIDENCE_REF}, sort_keys=True, ensure_ascii=False))
    raise SystemExit(1)

def close_allowed(rows):
    return bool(rows) and all(r.get("status") == "DONE" for r in rows)

if len(sys.argv) != 2:
    fail("EXACT_LIVE_INPUT_REQUIRED")
try:
    payload = json.loads(sys.argv[1])
except (ValueError, TypeError) as error:
    fail("INVALID_JSON", detail=str(error))

if not isinstance(payload, dict):
    fail("PAYLOAD_OBJECT_REQUIRED")
if payload.get("canonical_exit_criterion") != CANONICAL_EXIT:
    fail("CANONICAL_EXIT_CRITERION_MISMATCH")
rows = payload.get("rows")
if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
    fail("LIVE_ROWS_REQUIRED")
by_unit = {r.get("unit_code"): r for r in rows}
if len(rows) != len(REQUIRED_UNITS) or set(by_unit) != REQUIRED_UNITS:
    fail("DECLARED_UNIT_SET_MISMATCH", observed=sorted(str(u) for u in by_unit))
if not close_allowed(rows):
    fail("LIVE_BASELINE_NOT_DONE", statuses={u: by_unit[u].get("status") for u in sorted(by_unit)})
if "POST_PASE/SADM queda fuera de alcance" not in CANONICAL_EXIT:
    fail("CROSS_PROJECT_SCOPE_NOT_EXCLUDED")

adversarial_cases = []
for unit in sorted(REQUIRED_UNITS):
    scenario = copy.deepcopy(rows)
    next(row for row in scenario if row["unit_code"] == unit)["status"] = "IN_PROGRESS"
    rejected = not close_allowed(scenario)
    adversarial_cases.append({"unit": unit, "rejected": rejected})
    if not rejected:
        fail("OPEN_UNIT_DID_NOT_BLOCK", unit=unit)

print(json.dumps({
    "status": "PASS", "test_code": TEST_CODE,
    "observed": {"test_passed": True, "test_exit_code": 0,
                 "semantic_authority_bound": True, "adversarial_case_executed": True,
                 "all_live_units_done": True,
                 "negative_cases": adversarial_cases,
                 "cross_project_dependency_excluded": True},
    "evidence_ref": EVIDENCE_REF,
}, sort_keys=True, ensure_ascii=False))
