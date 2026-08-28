#!/usr/bin/env python3
from pathlib import Path
import json

root = Path(__file__).resolve().parents[2]
skill = root / "SKILL.md"
policy = root / "contracts" / "missing_input_policy.md"
schema = root / "schemas" / "ui_missing_input.schema.json"

text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:90])
policy_text = policy.read_text(encoding="utf-8")
schema_data = json.loads(schema.read_text(encoding="utf-8"))
actions = set(schema_data["properties"]["pipeline_action"]["enum"])

checks = {
    "critical_gate_salient": "RUNTIME CRITICAL GATE" in head,
    "defect_correction_postcondition_salient": "DEFECT -> CORRECTION -> POSTCONDITION" in head,
    "resolved_duplicate_short_circuit_salient": "RESOLVED DUPLICATE SHORT-CIRCUIT" in head,
    "single_redundant_target_rule_salient": "exactly one remediation action" in head and "redundant presentation" in head,
    "positive_survivor_example_salient": "Resumen` canonical + `top strip` redundant" in head and "top_amount_strip" in head and "payment_summary" in head,
    "full_production_spec_required_salient": "never abbreviate the output to a list of findings" in head and "PRODUCTION_UI_SPEC" in head,
    "unresolved_authority_short_circuit_salient": "UNRESOLVED AUTHORITY SHORT-CIRCUIT" in head,
    "missing_state_must_be_complete_json": "do not emit a bare pipeline-action token" in head,
    "return_to_orchestrator_positive_shape_salient": '"pipeline_action":"RETURN_TO_ORCHESTRATOR"' in head,
    "block_pipeline_condition_salient": "Use `BLOCK_PIPELINE` only when" in head,
    "policy_distinguishes_return_and_block": "RETURN_TO_ORCHESTRATOR" in policy_text and "BLOCK_PIPELINE" in policy_text,
    "pipeline_action_enum_complete": actions == {"CONTINUE_WITH_ASSUMPTIONS", "RETURN_TO_ORCHESTRATOR", "BLOCK_PIPELINE"},
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: salience gate reconciled with Missing Input Policy V2; resolved authority, RETURN_TO_ORCHESTRATOR and BLOCK_PIPELINE semantics are explicit")
