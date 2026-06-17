"""
validate_kb_entry_output.py
Validador de salida para SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF (ACT-0057)
"""
import json, sys
from typing import Any, Dict, List, Tuple

REQUIRED_FIELDS = ["run_id","operation_code","execution_mode","decision_upstream","kb_category","summary","key_insights","evidence_pack"]
REQUIRED_OPERATION_CODE = "ESCRITURA_BASE_CONOCIMIENTO_LF"
ALLOWED_UPSTREAM = {"ALLOW_PROD_GATE"}


def validate_kb_entry(output: Dict[str, Any]) -> Tuple[bool, List[str]]:
    errors = []

    for field in REQUIRED_FIELDS:
        if field not in output or output[field] is None:
            errors.append(f"MISSING_REQUIRED_FIELD: {field}")

    if output.get("operation_code") != REQUIRED_OPERATION_CODE:
        errors.append(f"INVALID_OPERATION_CODE: expected {REQUIRED_OPERATION_CODE}")

    if output.get("decision_upstream") not in ALLOWED_UPSTREAM:
        errors.append(f"UPSTREAM_DECISION_NOT_ALLOW: {output.get(decision_upstream)} not in {ALLOWED_UPSTREAM}")

    if not output.get("summary", "").strip():
        errors.append("SUMMARY_EMPTY")

    if not output.get("key_insights"):
        errors.append("KEY_INSIGHTS_EMPTY")

    return len(errors) == 0, errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_kb_entry_output.py <output.json>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        output = json.load(f)
    valid, errors = validate_kb_entry(output)
    if valid:
        print("VALIDATION_PASS")
        sys.exit(0)
    else:
        print("VALIDATION_FAIL")
        for e in errors: print(f"  - {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
