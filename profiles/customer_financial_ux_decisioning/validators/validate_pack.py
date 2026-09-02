#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ["README.md","SKILL.md","contracts/main_contract.md","contracts/input_governance_binding.json","schemas/output.schema.json","judges/score_rubric.md","judges/mini_judge.md","examples/good_output.json","examples/bad_output.json","evals/eval_matrix.json","handoffs/to_quality_pack.handoff.json","manifest.json"]
ALLOWED_OUTPUTS = {"CUSTOMER_FINANCIAL_DECISION_SPEC","MISSING_MATERIAL_FINANCIAL_INPUT","BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM"}
ALLOWED_TRIGGERS = {"input_not_governed_by_adapter","cross_adapter_conflict","profile_specific_constraint","authority_or_policy_uncertainty","critical_input_validation"}

def fail(code): raise SystemExit(f"CUSTOMER_FINANCIAL_UX_DECISIONING_FAIL:{code}")
for rel in REQUIRED:
    if not (ROOT/rel).is_file(): fail(f"MISSING:{rel}")
schema=json.loads((ROOT/"schemas/output.schema.json").read_text())
if set(schema["properties"]["output_type"]["enum"]) != ALLOWED_OUTPUTS: fail("OUTPUT_ENUM_MISMATCH")
binding=json.loads((ROOT/"contracts/input_governance_binding.json").read_text())
if binding.get("mode")!="selective" or binding.get("entrypoint")!="router_only": fail("INPUT_GOVERNANCE_NOT_SELECTIVE_ROUTER_ONLY")
if set(binding.get("allowed_triggers",[])) != ALLOWED_TRIGGERS: fail("INPUT_GOVERNANCE_TRIGGER_SET_MISMATCH")
if not binding.get("adapter_receipt_precedence") or not binding.get("duplicate_checks_forbidden"): fail("ADAPTER_RECEIPT_PRECEDENCE_MISSING")
if binding.get("outcomes",{}).get("BLOCK")!="fail_closed" or not binding.get("receipt_required"): fail("INPUT_GOVERNANCE_FAIL_CLOSED_MISSING")
manifest=json.loads((ROOT/"manifest.json").read_text())
if manifest.get("schema_version")!="lf-profile-pack-manifest/v1" or manifest.get("operation")!="CREACION_PERFIL_LF": fail("MANIFEST_CONTRACT")
if manifest.get("profile_code")!="CUSTOMER_FINANCIAL_UX_DECISIONING": fail("PROFILE_IDENTITY_MISMATCH")
if not set(REQUIRED).issubset(set(manifest.get("required_files",[]))): fail("MANIFEST_REQUIRED_FILES_INCOMPLETE")
if manifest.get("runtime_enabled") is not False or manifest.get("automatic_promotion") is not False: fail("RUNTIME_OR_AUTOPROMOTION_NOT_BLOCKED")
evals=json.loads((ROOT/"evals/eval_matrix.json").read_text())
cases=evals.get("cases",[])
if len(cases) < 10: fail("CHALLENGER_CASE_FLOOR_LT_10")
if evals.get("behavioral_execution_status")!="NOT_EXECUTED": fail("BEHAVIORAL_EVIDENCE_BOUNDARY")
case_types={c.get("type") for c in cases}
if not {"positive","negative","adversarial","equivalence","handoff"}.issubset(case_types): fail("EVAL_COVERAGE")
bad=json.loads((ROOT/"examples/bad_output.json").read_text())
if bad.get("self_verdict")!="READY_FOR_REVIEW" or bad.get("options",[{}])[0].get("authority_refs")!=[]: fail("NEGATIVE_FIXTURE")
skill=(ROOT/"SKILL.md").read_text()
for token in ["Never fabricate savings","UI Architect","Gamification System Architect","Router and direct execution"]:
    if token not in skill: fail(f"SKILL_GUARD_MISSING:{token}")
print("CUSTOMER_FINANCIAL_UX_DECISIONING_PACK_PASS")
