#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
CHAMPION_EVIDENCE = "evals/champion_challenger_structural_20260902.json"
SEMANTIC_JUDGE = "judges/semantic_judge.md"
REQUIRED = [
    "README.md","SKILL.md","contracts/main_contract.md","contracts/input_governance_binding.json",
    "schemas/output.schema.json","judges/score_rubric.md","judges/mini_judge.md",SEMANTIC_JUDGE,
    "examples/good_output.json","examples/bad_output.json","evals/eval_matrix.json",CHAMPION_EVIDENCE,
    "handoffs/to_quality_pack.handoff.json","manifest.json"
]
CANONICAL_CORE = [
    "SKILL.md","README.md","contracts/main_contract.md","schemas/output.schema.json",
    "judges/score_rubric.md","judges/mini_judge.md","evals/eval_matrix.json",
    "handoffs/to_quality_pack.handoff.json","examples/good_output.json","examples/bad_output.json","manifest.json"
]
ALLOWED_OUTPUTS = {"CUSTOMER_FINANCIAL_DECISION_SPEC","MISSING_MATERIAL_FINANCIAL_INPUT","BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM"}
ALLOWED_TRIGGERS = {"input_not_governed_by_adapter","cross_adapter_conflict","profile_specific_constraint","authority_or_policy_uncertainty","critical_input_validation"}
# Historical champion evidence remains immutable provenance; it is not the current maturity authority.
EXPECTED_HISTORICAL_CHAMPION_BLOBS={"UI_ARCHITECT":"0e9105bf37171f28bafe6602d3012f59002cbe88","GAMIFICATION_SYSTEM_ARCHITECT":"5e805cb355da421a76c917e965f2971675e80a9e"}
CURRENT_UI_ARCHITECT_BENCHMARK_BLOB="88e74821fc8715dde173586772b888e20aa791ea"

def fail(code):
    raise SystemExit(f"CUSTOMER_FINANCIAL_UX_DECISIONING_FAIL:{code}")

for rel in REQUIRED:
    if not (ROOT/rel).is_file():
        fail(f"MISSING:{rel}")

schema=json.loads((ROOT/"schemas/output.schema.json").read_text())
if set(schema["properties"]["output_type"]["enum"]) != ALLOWED_OUTPUTS:
    fail("OUTPUT_ENUM_MISMATCH")

binding=json.loads((ROOT/"contracts/input_governance_binding.json").read_text())
if binding.get("mode")!="selective" or binding.get("entrypoint")!="router_only":
    fail("INPUT_GOVERNANCE_NOT_SELECTIVE_ROUTER_ONLY")
if set(binding.get("allowed_triggers",[])) != ALLOWED_TRIGGERS:
    fail("INPUT_GOVERNANCE_TRIGGER_SET_MISMATCH")
if not binding.get("adapter_receipt_precedence") or not binding.get("duplicate_checks_forbidden"):
    fail("ADAPTER_RECEIPT_PRECEDENCE_MISSING")
if binding.get("outcomes",{}).get("BLOCK")!="fail_closed" or not binding.get("receipt_required"):
    fail("INPUT_GOVERNANCE_FAIL_CLOSED_MISSING")

manifest=json.loads((ROOT/"manifest.json").read_text())
if manifest.get("schema_version")!="lf-profile-pack-manifest/v1" or manifest.get("operation")!="CREACION_PERFIL_LF":
    fail("MANIFEST_CREATION_PROVENANCE_CONTRACT")
if manifest.get("maintenance_operation")!="ACTUALIZACION_PERFIL_LF":
    fail("MANIFEST_UPDATE_OPERATION_MISSING")
if manifest.get("profile_code")!="CUSTOMER_FINANCIAL_UX_DECISIONING":
    fail("PROFILE_IDENTITY_MISMATCH")
if not set(REQUIRED).issubset(set(manifest.get("required_files",[]))):
    fail("MANIFEST_REQUIRED_FILES_INCOMPLETE")
if manifest.get("runtime_enabled") is not False or manifest.get("automatic_promotion") is not False:
    fail("RUNTIME_OR_AUTOPROMOTION_NOT_BLOCKED")
if manifest.get("behavioral_proof_status")!="NOT_EXECUTED" or manifest.get("governed_creation_receipt_status")!="PENDING_CANONICAL_EXECUTION":
    fail("EVIDENCE_BOUNDARY_DRIFT")
benchmark=manifest.get("maturity_benchmark",{})
if benchmark.get("profile_code")!="PERFIL-UI-ARCHITECT" or benchmark.get("skill_blob")!=CURRENT_UI_ARCHITECT_BENCHMARK_BLOB:
    fail("CURRENT_UI_MATURITY_BENCHMARK_MISSING_OR_STALE")
if benchmark.get("usage")!="TRANSVERSE_MATURITY_PATTERN_ONLY_NOT_DOMAIN_AUTHORITY":
    fail("BENCHMARK_DOMAIN_BOUNDARY")

# Eval design must now contain explicit depth, counterfactual and unseen-holdout coverage.
evals=json.loads((ROOT/"evals/eval_matrix.json").read_text())
if evals.get("schema_version")!="PROFILE_EVAL_MATRIX_V3_DEPTH":
    fail("EVAL_MATRIX_VERSION")
cases=evals.get("cases",[])
if len(cases) < 15:
    fail("DEPTH_CASE_FLOOR_LT_15")
if evals.get("behavioral_execution_status")!="NOT_EXECUTED":
    fail("BEHAVIORAL_EVIDENCE_BOUNDARY")
case_types={c.get("type") for c in cases}
required_types={"positive","negative","adversarial","equivalence","handoff","counterfactual","depth","holdout"}
if not required_types.issubset(case_types):
    fail("EVAL_DEPTH_COVERAGE")
holdout=evals.get("holdout_policy",{})
if holdout.get("minimum_unseen_holdout",0) < 1 or holdout.get("holdout_must_not_be_used_to_author_profile") is not True:
    fail("UNSEEN_HOLDOUT_POLICY")
if not any(c.get("type")=="holdout" and c.get("freshness")=="UNSEEN_RESERVED" for c in cases):
    fail("UNSEEN_HOLDOUT_CASE_MISSING")

# Preserve historical structural comparison as provenance only.
champ=json.loads((ROOT/CHAMPION_EVIDENCE).read_text())
if champ.get("schema_version")!="customer-profile-champion-challenger/v1" or champ.get("comparison_type")!="SOURCE_BOUND_STRUCTURAL_ONLY":
    fail("CHAMPION_EVIDENCE_CONTRACT")
if champ.get("challenger",{}).get("behavioral_execution_status")!="NOT_EXECUTED":
    fail("CHAMPION_BEHAVIORAL_OVERCLAIM")
observed_blobs={c.get("profile"):c.get("git_blob") for c in champ.get("champions",[])}
if observed_blobs!=EXPECTED_HISTORICAL_CHAMPION_BLOBS:
    fail("HISTORICAL_CHAMPION_SOURCE_PIN_MISMATCH")
if champ.get("dimensions",{}).get("latency",{}).get("source_status")!="NOT_OBSERVED":
    fail("LATENCY_OVERCLAIM")
if champ.get("verdict")!="READY_FOR_BEHAVIORAL_EXECUTION_NOT_BEHAVIORAL_PASS":
    fail("CHAMPION_VERDICT_OVERCLAIM")

bad=json.loads((ROOT/"examples/bad_output.json").read_text())
if bad.get("self_verdict")!="READY_FOR_REVIEW" or bad.get("options",[{}])[0].get("authority_refs")!=[]:
    fail("NEGATIVE_FIXTURE")

skill=(ROOT/"SKILL.md").read_text()
for token in [
    "Never fabricate savings","UI Architect","Router/direct equivalence","COUNTERFACTUAL CHECK",
    "CAUSAL CONSEQUENCES, NOT LABELS","BEHAVIORAL PROOF BOUNDARY"
]:
    if token.lower() not in skill.lower():
        fail(f"SKILL_DEPTH_GUARD_MISSING:{token}")

contract=(ROOT/"contracts/main_contract.md").read_text()
for token in ["Golden-capable depth contract","Counterfactual / alternative challenge contract","Behavioral proof contract"]:
    if token not in contract:
        fail(f"CONTRACT_DEPTH_GUARD_MISSING:{token}")

rubric=(ROOT/"judges/score_rubric.md").read_text()
for token in ["tradeoff_and_counterfactual_depth","NEEDS_REPAIR","handoff_integrity_and_postcondition"]:
    if token not in rubric:
        fail(f"RUBRIC_DEPTH_GUARD_MISSING:{token}")

semantic=(ROOT/SEMANTIC_JUDGE).read_text()
for token in ["Counterfactual challenge procedure","Causal consequence depth","Router/direct consistency","Claim ceiling"]:
    if token not in semantic:
        fail(f"SEMANTIC_JUDGE_DEPTH_GUARD_MISSING:{token}")

canonical_path = REPO_ROOT / "skills/profile_creator/validators/validate_candidate_depth.py"
spec = importlib.util.spec_from_file_location("lf_profile_creator_canonical_depth", canonical_path)
if spec is None or spec.loader is None:
    fail("CANONICAL_DEPTH_VALIDATOR_LOAD")
canonical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(canonical)
files = {rel: (ROOT/rel).read_text(encoding="utf-8") for rel in CANONICAL_CORE}
pack = {
    "artifact_type": "PROFILE_PACK_CANDIDATE",
    "profile_pack_id": manifest.get("profile_pack_id") or "CUSTOMER_FINANCIAL_UX_DECISIONING_PROFILE_PACK_001",
    "source_authority": "lf://authority/CREACION_PERFIL_LF + governed current maturity benchmark",
    "document_status": "CANDIDATO",
    "operational_status": "READ_ONLY",
    "runtime_enabled": False,
    "runtime": "NO_HABILITADO",
    "automatic_impact": "BLOQUEADO",
    "production_authorization": False,
    "exposes_user_facing_output": False,
    "evidence_map": [{"source_ref":"lf://authority/ACTUALIZACION_PERFIL_LF","supports":["governed existing-profile maintenance authority","candidate read-only boundary"]}],
    "files": files,
}
blocking, warnings = canonical.validate_candidate(pack)
if blocking:
    fail("CANONICAL_DEPTH:" + "|".join(blocking))

print("CUSTOMER_FINANCIAL_UX_DECISIONING_SEMANTIC_DEPTH_ASSETS_PASS")
print("CUSTOMER_FINANCIAL_UX_DECISIONING_UNSEEN_HOLDOUT_DESIGN_PASS")
print("CUSTOMER_FINANCIAL_UX_DECISIONING_CANONICAL_DEPTH_READY_FOR_BEHAVIORAL_EXECUTION")
print("CUSTOMER_FINANCIAL_UX_DECISIONING_PACK_PASS")
