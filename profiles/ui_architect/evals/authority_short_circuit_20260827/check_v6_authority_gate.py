#!/usr/bin/env python3
from pathlib import Path
import json

skill = Path(__file__).resolve().parents[2] / "SKILL.md"
text = skill.read_text(encoding="utf-8")
head = "\n".join(text.splitlines()[:105])

checks = {
    "critical_gate_first": "RUNTIME CRITICAL GATE" in head,
    "final_output_byte_rule": "FINAL OUTPUT BYTE RULE" in head and "Never emit backticks" in head,
    "authority_triage_hard_precedence": "AUTHORITY TRIAGE FIRST — HARD PRECEDENCE" in head,
    "explicit_unresolved_outranks_hierarchy": "explicit unresolved-authority statement outranks" in head and "Never infer `payment_summary`" in head,
    "explicit_do_not_guess_short_circuit": "explicitly says not to guess the survivor" in head and "immediately use the unresolved-authority short-circuit" in head,
    "complete_missing_state": '"self_verdict":"NEEDS_INPUT"' in head and '"pipeline_action":"RETURN_TO_ORCHESTRATOR"' in head,
    "missing_state_stop": "emit exactly one complete Missing Input State JSON object and STOP generation immediately" in head,
    "resolved_path_guarded": "This path is legal only when `authority_resolved=true`" in head,
    "single_destructive_redundant_target": "exactly one remediation action" in head and "redundant presentation" in head,
    "action_binding_first": "ACTION BINDING FIRST" in head and "evidence_component_ids` before `evidence_anchor" in head,
    "no_full_example_priming": "NO FULL PRODUCTION EXAMPLE PRIMING" in head and "complete example Production UI Spec" in head,
    "legacy_full_example_removed": "Compact positive resolved-duplicate shape to follow" not in head,
    "root_tail_closure_sentinel": "ROOT-TAIL CLOSURE SENTINEL" in head and "Close `deliverable_created`" in head,
    "score_closure_sentinel": "SCORE CLOSURE SENTINEL" in head and "close `evidence_by_criterion`, then close `score`" in head,
    "root_serialization_order": "worker -> output_type -> deliverable_created -> CLOSE deliverable_created -> score -> CLOSE score -> handoff_to_next -> CLOSE handoff_to_next -> self_verdict -> CLOSE root" in head,
    "score_nesting_repair": "if `handoff_to_next` or `self_verdict` is nested under `score`" in head,
    "single_json_envelope": "SINGLE JSON ENVELOPE" in head and "exactly one JSON object and nothing else" in head,
    "zero_fence_contract": "zero backticks" in head and "Markdown fences" in head,
    "stop_after_final_object": "stop generation immediately" in head and "Never restart the envelope" in head,
}

print(json.dumps(checks, ensure_ascii=False, indent=2))
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: V12 frontloads explicit unresolved-authority fail-closed behavior and closes score before root handoff")
