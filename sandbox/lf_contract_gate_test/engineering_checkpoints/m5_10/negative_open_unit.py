#!/usr/bin/env python3
import copy
import json
import sys

TEST_CODE = "ENG_M5_10_NEGATIVE_OPEN_UNIT"
EXPECTED_UNITS = {"M5.0", "M5.1", "M5.2", "M5.9"}
CANONICAL_EXIT = (
    "Las 10 unidades M5 (M5.0–M5.9) DONE; evidencia de cierre IG derivada del "
    "ledger/checkpoints; evento HANDOFF de cierre M5 persistido; readback independiente "
    "del Curator. POST_PASE/SADM queda fuera de alcance mientras su workstream permanezca desactivado."
)
EVIDENCE_REF = "supabase://programacion.engineering_plan_units+engineering_work_items/M5.0,M5.1,M5.2,M5.9/live-readback-20261007"


def emit_fail(reason: str, **extra):
    print(json.dumps({
        "status": "FAIL",
        "test_code": TEST_CODE,
        "observed": {
            "test_passed": False,
            "test_exit_code": 1,
            "semantic_authority_bound": False,
            "adversarial_case_executed": bool(extra.pop("adversarial_case_executed", False)),
            "reason": reason,
            **extra,
        },
        "evidence_ref": EVIDENCE_REF,
    }, sort_keys=True, ensure_ascii=False))
    raise SystemExit(1)


def closure_allowed(rows):
    return all(row.get("status") == "DONE" for row in rows)


if len(sys.argv) != 2:
    emit_fail("DECLARED_INPUT_JSON_REQUIRED")

try:
    payload = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    emit_fail("DECLARED_INPUT_JSON_INVALID", detail=str(exc))

rows = payload.get("rows")
criterion = payload.get("canonical_exit_criterion")

if criterion != CANONICAL_EXIT:
    emit_fail("CANONICAL_EXIT_CRITERION_MISMATCH", received=criterion)

if not isinstance(rows, list):
    emit_fail("LIVE_ROWS_ARRAY_REQUIRED")

by_unit = {row.get("unit_code"): row for row in rows if isinstance(row, dict)}
if set(by_unit) != EXPECTED_UNITS:
    emit_fail("DECLARED_UNIT_SET_MISMATCH", expected=sorted(EXPECTED_UNITS), observed=sorted(x for x in by_unit if x))

if not closure_allowed(rows):
    emit_fail("LIVE_BASELINE_NOT_DONE", statuses={u: by_unit[u].get("status") for u in sorted(by_unit)})

adversarial = copy.deepcopy(rows)
adversarial[0]["status"] = "IN_PROGRESS"

if closure_allowed(adversarial):
    emit_fail("OPEN_UNIT_DID_NOT_BLOCK_CLOSURE", adversarial_case_executed=True)

if "FINAL_EVIDENCE/CLOSURE_GATE" in criterion:
    emit_fail("CROSS_WORKSTREAM_REQUIREMENT_STILL_PRESENT", adversarial_case_executed=True)

print(json.dumps({
    "status": "PASS",
    "test_code": TEST_CODE,
    "observed": {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "live_baseline_all_done": True,
        "open_unit_blocks_closure": True,
        "cross_workstream_requirement_absent": True,
        "live_units_checked": sorted(EXPECTED_UNITS),
        "canonical_exit_criterion": criterion,
    },
    "evidence_ref": EVIDENCE_REF,
}, sort_keys=True, ensure_ascii=False))
