#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPO_ROOT=ROOT.parents[1]
CHAMPION_EVIDENCE="evals/champion_challenger_structural_20260902.json"
REQUIRED=["README.md","SKILL.md","contracts/main_contract.md","contracts/input_governance_binding.json","schemas/output.schema.json","judges/score_rubric.md","judges/mini_judge.md","examples/good_output.json","examples/bad_output.json","evals/eval_matrix.json",CHAMPION_EVIDENCE,"handoffs/to_quality_pack.handoff.json","manifest.json"]
CANONICAL_CORE=["SKILL.md","README.md","contracts/main_contract.md","schemas/output.schema.json","judges/score_rubric.md","judges/mini_judge.md","evals/eval_matrix.json","handoffs/to_quality_pack.handoff.json","examples/good_output.json","examples/bad_output.json","manifest.json"]
ALLOWED_STATES={"NOT_STARTED","PENDING","SUCCEEDED","FAILED_RETRYABLE","FAILED_NONRETRYABLE","UNKNOWN"}
ALLOWED_TRIGGERS={"input_not_governed_by_adapter","cross_adapter_conflict","profile_specific_constraint","authority_or_policy_uncertainty","critical_input_validation"}
EXPECTED_CHAMPION_BLOBS={"UI_ARCHITECT":"0e9105bf37171f28bafe6602d3012f59002cbe88","GAMIFICATION_SYSTEM_ARCHITECT":"5e805cb355da421a76c917e965f2971675e80a9e"}
def fail(code): raise SystemExit(f"CUSTOMER_PAYMENTS_RECOVERY_FAIL:{code}")
for rel in REQUIRED:
    if not (ROOT/rel).is_file(): fail(f"MISSING:{rel}")
schema=json.loads((ROOT/"schemas/output.schema.json").read_text())
if set(schema["properties"]["payment_state"]["enum"])!=ALLOWED_STATES: fail("PAYMENT_STATE_ENUM_MISMATCH")
binding=json.loads((ROOT/"contracts/input_governance_binding.json").read_text())
if binding.get("mode")!="selective" or binding.get("entrypoint")!="router_only": fail("INPUT_GOVERNANCE_NOT_SELECTIVE_ROUTER_ONLY")
if set(binding.get("allowed_triggers",[]))!=ALLOWED_TRIGGERS: fail("INPUT_GOVERNANCE_TRIGGER_SET_MISMATCH")
if binding.get("outcomes",{}).get("BLOCK")!="fail_closed" or not binding.get("receipt_required"): fail("INPUT_GOVERNANCE_FAIL_CLOSED_MISSING")
manifest=json.loads((ROOT/"manifest.json").read_text())
if manifest.get("schema_version")!="lf-profile-pack-manifest/v1" or manifest.get("operation")!="CREACION_PERFIL_LF": fail("MANIFEST_CONTRACT")
if manifest.get("profile_code")!="CUSTOMER_PAYMENTS_RECOVERY": fail("PROFILE_IDENTITY_MISMATCH")
if manifest.get("runtime_enabled") is not False or manifest.get("automatic_promotion") is not False: fail("RUNTIME_OR_AUTOPROMOTION_NOT_BLOCKED")
if not set(REQUIRED).issubset(set(manifest.get("required_files",[]))): fail("MANIFEST_REQUIRED_FILES_INCOMPLETE")
if manifest.get("behavioral_proof_status")!="NOT_EXECUTED" or manifest.get("governed_creation_receipt_status")!="PENDING_CANONICAL_EXECUTION": fail("EVIDENCE_BOUNDARY_DRIFT")
evals=json.loads((ROOT/"evals/eval_matrix.json").read_text()); cases=evals.get("cases",[])
if len(cases)<10: fail("CHALLENGER_CASE_FLOOR_LT_10")
if evals.get("behavioral_execution_status")!="NOT_EXECUTED": fail("BEHAVIORAL_EVIDENCE_BOUNDARY")
if not {"positive","negative","adversarial","equivalence","handoff"}.issubset({c.get("type") for c in cases}): fail("EVAL_COVERAGE")
champ=json.loads((ROOT/CHAMPION_EVIDENCE).read_text())
if champ.get("schema_version")!="customer-profile-champion-challenger/v1" or champ.get("comparison_type")!="SOURCE_BOUND_STRUCTURAL_ONLY": fail("CHAMPION_EVIDENCE_CONTRACT")
if champ.get("challenger",{}).get("behavioral_execution_status")!="NOT_EXECUTED": fail("CHAMPION_BEHAVIORAL_OVERCLAIM")
if {c.get("profile"):c.get("git_blob") for c in champ.get("champions",[])}!=EXPECTED_CHAMPION_BLOBS: fail("CHAMPION_SOURCE_PIN_MISMATCH")
if champ.get("dimensions",{}).get("latency",{}).get("source_status")!="NOT_OBSERVED": fail("LATENCY_OVERCLAIM")
if champ.get("verdict")!="READY_FOR_BEHAVIORAL_EXECUTION_NOT_BEHAVIORAL_PASS": fail("CHAMPION_VERDICT_OVERCLAIM")
bad=json.loads((ROOT/"examples/bad_output.json").read_text())
if bad.get("payment_state")!="SUCCEEDED" or bad.get("state_evidence_refs")!=[]: fail("NEGATIVE_FIXTURE_STATE_DEFECT_REMOVED")
if bad.get("retry_policy",{}).get("idempotency_requirement")!="none": fail("NEGATIVE_FIXTURE_RETRY_DEFECT_REMOVED")
skill=(ROOT/"SKILL.md").read_text().lower()
for token in ["never retry blindly","timeout","duplicate","ui architect","gamification system architect"]:
    if token not in skill: fail(f"SKILL_GUARD_MISSING:{token}")
canonical_path=REPO_ROOT/"skills/profile_creator/validators/validate_candidate_depth.py"
spec=importlib.util.spec_from_file_location("lf_profile_creator_canonical_depth",canonical_path)
if spec is None or spec.loader is None: fail("CANONICAL_DEPTH_VALIDATOR_LOAD")
canonical=importlib.util.module_from_spec(spec); spec.loader.exec_module(canonical)
files={rel:(ROOT/rel).read_text(encoding="utf-8") for rel in CANONICAL_CORE}
pack={"artifact_type":"PROFILE_PACK_CANDIDATE","profile_pack_id":manifest.get("profile_pack_id") or "CUSTOMER_PAYMENTS_RECOVERY_PROFILE_PACK_001","source_authority":"lf://authority/CREACION_PERFIL_LF + governed champion references","document_status":"CANDIDATO","operational_status":"READ_ONLY","runtime_enabled":False,"runtime":"NO_HABILITADO","automatic_impact":"BLOQUEADO","production_authorization":False,"exposes_user_facing_output":False,"evidence_map":[{"source_ref":"lf://authority/CREACION_PERFIL_LF","supports":["governed profile creation authority","candidate read-only boundary"]}],"files":files}
blocking,warnings=canonical.validate_candidate(pack)
if blocking: fail("CANONICAL_DEPTH:"+"|".join(blocking))
print("CUSTOMER_PAYMENTS_RECOVERY_CHAMPION_EVIDENCE_PASS")
print("CUSTOMER_PAYMENTS_RECOVERY_CANONICAL_DEPTH_READY_FOR_SEMANTIC_REVIEW")
print("CUSTOMER_PAYMENTS_RECOVERY_PACK_PASS")
