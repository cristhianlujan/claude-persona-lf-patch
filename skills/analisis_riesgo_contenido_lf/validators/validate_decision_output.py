"""
validate_decision_output.py
Validador de salida para SKILL_ANALISIS_RIESGO_CONTENIDO_LF (ACT-0056)
Patron: Guardrails-AI style validator
"""
import json
import sys
from typing import Any, Dict, List, Tuple

ALLOWED_DECISIONS = {
    "ALLOW_CANDIDATE_READ_ONLY",
    "ALLOW_PROD_GATE",
    "RESEARCH_OR_HITL",
    "HITL_REQUIRED",
    "BLOCK_OR_HITL",
}

REQUIRED_FIELDS = [
    "run_id",
    "operation_code",
    "execution_mode",
    "decision",
    "decision_reason",
    "evidence_pack",
]

REQUIRED_OPERATION_CODE = "ANALISIS_RIESGO_CONTENIDO_LF"


def validate_decision_output(output: Dict[str, Any]) -> Tuple[bool, List[str]]:
    errors = []

    # Check required fields
    for field in REQUIRED_FIELDS:
        if field not in output or output[field] is None:
            errors.append(f"MISSING_REQUIRED_FIELD: {field}")

    # Check operation_code
    if output.get("operation_code") != REQUIRED_OPERATION_CODE:
        errors.append(f"INVALID_OPERATION_CODE: expected {REQUIRED_OPERATION_CODE}")

    # Check decision value
    decision = output.get("decision")
    if decision not in ALLOWED_DECISIONS:
        errors.append(f"DECISION_OUTSIDE_SCHEMA: {decision} not in {ALLOWED_DECISIONS}")

    # Check P0/P1 without HITL
    p0_p1_flags = output.get("p0_p1_flags", [])
    hitl_required = output.get("hitl_required", False)
    if p0_p1_flags and not hitl_required and decision not in {"HITL_REQUIRED", "BLOCK_OR_HITL"}:
        errors.append("P0_P1_WITHOUT_HITL: P0/P1 flags present but hitl_required=False and decision not HITL/BLOCK")

    # Check evidence_pack not empty when decision is ALLOW
    if decision in {"ALLOW_CANDIDATE_READ_ONLY", "ALLOW_PROD_GATE"}:
        if not output.get("evidence_pack"):
            errors.append("EVIDENCE_PACK_EMPTY_ON_ALLOW: evidence required for ALLOW decisions")

    return len(errors) == 0, errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_decision_output.py <output.json>")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        output = json.load(f)

    valid, errors = validate_decision_output(output)

    if valid:
        print("VALIDATION_PASS")
        sys.exit(0)
    else:
        print("VALIDATION_FAIL")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
