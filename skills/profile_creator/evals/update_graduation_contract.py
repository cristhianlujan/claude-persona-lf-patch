#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILL_ROOT = ROOT / "skills/profile_creator"
CONTRACT = json.loads((SKILL_ROOT / "contracts/update_graduation_contract_v1.json").read_text(encoding="utf-8"))
GATE_SQL = (ROOT / "supabase/migrations/20260915161601_lf_profile_update_substantive_gate_v1.sql").read_text(encoding="utf-8")
RECORDER_SQL = (ROOT / "supabase/migrations/20260915161619_lf_profile_update_recorder_substantive_gate_v1.sql").read_text(encoding="utf-8")
RUNTIME = (ROOT / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")
GRADUATION = (ROOT / "supabase/functions/run-creacion-perfil-lf/graduation.ts").read_text(encoding="utf-8")

checks = {
    "contract_is_additive_not_authority": CONTRACT["authorization_semantics"]["adds_permissions"] is False
        and CONTRACT["authorization_semantics"]["runtime_enable"] is False
        and CONTRACT["authorization_semantics"]["automatic_promotion"] is False
        and CONTRACT["authorization_semantics"]["golden_declaration"] is False
        and CONTRACT["authorization_semantics"]["production_authorization"] is False,
    "single_canonical_update_recorder": "create or replace function public.lf_record_profile_operation_step_v1" not in GATE_SQL
        and "lf_record_actualizacion_perfil_step" not in GATE_SQL + RECORDER_SQL + RUNTIME,
    "recorder_binds_substantive_gate": "lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest)" in RECORDER_SQL,
    "explicit_validator_fail_is_derived": "PROFILE_UPDATE_VALIDATOR_RESULT_FAILED" in GATE_SQL,
    "semantic_fail_is_derived": "PROFILE_UPDATE_SEMANTIC_JUDGE_FAILED" in GATE_SQL,
    "adversarial_and_holdout_fail_are_derived": "PROFILE_UPDATE_ADVERSARIAL_FAILED" in GATE_SQL and "PROFILE_UPDATE_HOLDOUT_FAILED" in GATE_SQL,
    "fixture_completeness_is_mandatory_for_golden": "PROFILE_UPDATE_GOLDEN_FIXTURE_CASES_MISSING" in GATE_SQL and "declared_case_count" in GATE_SQL and "delivered_fixture_count" in GATE_SQL,
    "raw_governed_and_unseen_holdout_required": "PROFILE_UPDATE_GOLDEN_RAW_GOVERNED_RUNS_MISSING" in GATE_SQL and "PROFILE_UPDATE_GOLDEN_UNSEEN_HOLDOUT_NOT_EXECUTED" in GATE_SQL,
    "independent_semantic_required": "PROFILE_UPDATE_GOLDEN_INDEPENDENT_SEMANTIC_UNPROVEN" in GATE_SQL and "PROFILE_UPDATE_GOLDEN_INDEPENDENT_EVALUATION_MISSING" in GATE_SQL,
    "no_aggregate_masking_required": "PROFILE_UPDATE_GOLDEN_NO_AGGREGATE_MASKING_UNPROVEN" in GATE_SQL,
    "caller_cannot_supply_server_receipt_verdict": "...GRADUATION_SERVER_FIELDS" in RUNTIME and "server_contract_receipt_verified" in GRADUATION,
    "receipt_read_from_exact_readback_head": "github_readback" in GRADUATION and "exactHead" in GRADUATION and "GITHUB_GRADUATION_RECEIPT" in GRADUATION,
    "receipt_identity_bound_to_execution": "receipt?.execution_id === ex.execution_id" in GRADUATION and "receipt?.operation_code === \"ACTUALIZACION_PERFIL_LF\"" in GRADUATION,
    "receipt_requires_clean_contract_judge": "all_required_steps_pass !== true" in GRADUATION and "blocking_codes" in GRADUATION and "contract_sha" in GRADUATION and "judge_sha" in GRADUATION,
    "db_close_requires_server_verified_receipt": "PROFILE_UPDATE_GOLDEN_CONTRACT_RECEIPT_UNVERIFIED" in GATE_SQL and "PROFILE_UPDATE_GOLDEN_RECEIPT_HEAD_MISMATCH" in GATE_SQL,
    "ordinary_mode_still_supported": CONTRACT["ordinary_update_compatibility"]["graduation_contract_absent"].startswith("existing ACTUALIZACION_PERFIL_LF flow remains"),
}

failed = [name for name, ok in checks.items() if not ok]
print(json.dumps({
    "status": "PASS" if not failed else "FAIL",
    "checks": checks,
    "failed": failed,
    "evidence_level": "ARTIFACT_BOUND_SOURCE_REGRESSION",
    "runtime_proof": "NOT_CLAIMED_FRESH_CANARY_REQUIRED",
    "mass_rollout_authorized": False,
}, indent=2))
raise SystemExit(0 if not failed else 1)