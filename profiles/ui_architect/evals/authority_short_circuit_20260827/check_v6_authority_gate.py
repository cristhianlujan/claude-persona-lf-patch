#!/usr/bin/env python3
from pathlib import Path
import json

skill = Path(__file__).resolve().parents[2] / "SKILL.md"
text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:105])

checks = {
    "critical_gate_first": "RUNTIME CRITICAL GATE" in head,
    "final_output_byte_rule": "FINAL OUTPUT BYTE RULE" in head and "zero backticks" in head,
    "authority_resolution_first": "AUTHORITY RESOLUTION FIRST" in head,
    "resolved_duplicate_short_circuit": "RESOLVED DUPLICATE SHORT-CIRCUIT" in head,
    "single_destructive_redundant_target": "exactly one remediation action" in head and "redundant presentation" in head,
    "action_binding_first": "ACTION BINDING FIRST" in head and "evidence_component_ids` before `evidence_anchor" in head,
    "root_tail_closure_sentinel": "ROOT-TAIL CLOSURE SENTINEL" in head and "CLOSE `deliverable_created`" in head,
    "root_tail_serialization_order": "worker -> output_type -> deliverable_created -> CLOSE deliverable_created -> score -> handoff_to_next -> self_verdict -> CLOSE root" in head,
    "nested_root_tail_repair": "deliverable_created.score" in head and "deliverable_created.handoff_to_next" in head and "deliverable_created.self_verdict" in head,
    "positive_resumen_survivor_example": "Resumen` canonical + `top strip` redundant" in head and "top_amount_strip" in head and "payment_summary" in head,
    "survivor_kept_out_of_remediation_target": "not as a remediation target" in head,
    "full_production_spec_required": "never abbreviate the output to a list of findings" in head and "PRODUCTION_UI_SPEC" in head,
    "single_json_envelope_required": "SINGLE JSON ENVELOPE" in head and "exactly one JSON object and nothing else" in head,
    "top_level_fields_exactly_once": "must each appear exactly once" in head and "root-tail keys at ROOT depth only" in head,
    "evidence_target_binding_required": "evidence_component_ids` is mandatory" in head and "execution.target_component_id" in head,
    "positive_examples_not_markdown_fenced": "```json" not in head and "plain JSON object" in head,
    "stop_after_final_object": "stop generation immediately" in head and "Never restart the envelope" in head,
    "unresolved_authority_short_circuit": "UNRESOLVED AUTHORITY SHORT-CIRCUIT" in head,
    "complete_missing_state_not_bare_token": "do not emit a bare pipeline-action token" in head,
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: V11 preserves semantic survivor/binding behavior and enforces root-tail closure before score/handoff/verdict")
