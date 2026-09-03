from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CALLER = ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts"
BATCH = ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/batch.ts"
RUNTIME = ROOT / "supabase/functions/run-creacion-perfil-lf/index.ts"
WORKFLOW = ROOT / ".github/workflows/lf-customer-profile-creator-governance-caller.yml"
RECORDER = ROOT / "supabase/migrations/20260902233217_profile_creator_step_status_contract_fix.sql"

caller = CALLER.read_text(encoding="utf-8")
batch = BATCH.read_text(encoding="utf-8")
runtime = RUNTIME.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")
recorder = RECORDER.read_text(encoding="utf-8")

checks = {
    "exclusive_branch": 'lf/profiles/profile-creator-customer-caller-20260902' in caller and 'lf/profiles/profile-creator-customer-caller-20260902' in workflow,
    "exclusive_workflow": 'LF Customer Profile Creator Governance Caller' in caller and 'LF Customer Profile Creator Governance Caller' in workflow,
    "oidc_exact_repo": all(token in caller for token in ['OIDC_REPOSITORY_MISMATCH', 'OIDC_REF_MISMATCH', 'OIDC_WORKFLOW_MISMATCH']),
    "project_identity": 'AGENTE_PROFILE_CREATOR' in caller,
    "lane_identity": 'CUSTOMER_PROFILES' in caller and 'LF-CUSTOMER-PROFILES' not in caller,
    "origin_identity": 'AUTOMATION_PROFILE_CREATOR_DUAL_EXECUTOR' in caller,
    "workstream_identity": 'PROFILE_CREATOR_INFRA' in caller,
    "customer_allowlist": all(code in caller for code in [
        'PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING',
        'PERFIL-CUSTOMER-TRUST-CLARITY-VULNERABILITY',
        'PERFIL-CUSTOMER-PAYMENTS-RECOVERY',
        'PERFIL-CUSTOMER-IDENTITY-CONSENT-PRIVACY',
    ]),
    "generic_next_step_action": 'profile_operation_next_step_v1' in caller and 'next_profile_operation_step_v1' in runtime,
    "generic_record_step_action": 'profile_operation_record_step_v1' in caller and 'record_profile_operation_step_v1' in runtime,
    "generic_record_batch_action": 'profile_operation_record_batch_v1' in caller,
    "compat_creation_actions_preserved": 'profile_creator_init_v1' in caller and 'profile_creator_record_step_v1' in caller and 'profile_creator_record_batch_v1' in caller,
    "runtime_delegate_only": 'run-creacion-perfil-lf' in caller and 'lf_record_creacion_perfil_step_v1' not in caller,
    "no_manual_db_step_write": 'lf_operation_execution_steps' not in caller and '.from(' not in caller,
    "no_input_governance_actions": 'input_readiness_' not in caller and 'input-governance-agent-v1' not in caller,
    "no_adapter_actions": 'adapter' not in caller.lower(),
    "no_receipt_fabrication": 'LF_OPERATION_CONTRACT_RECEIPT' not in caller and 'LF_OPERATION_CONTRACT_RECEIPT' not in workflow,
    "currentness_before_batch_write": 'PROFILE_OPERATION_BATCH_STEP_NOT_CURRENT' in caller and 'expectedStepId !== step.step_id' in caller,
    "currentness_inside_runtime": 'PROFILE_OPERATION_STEP_NOT_CURRENT' in runtime,
    "update_fail_closed_without_recorder": 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in runtime,
    "creation_uses_canonical_recorder": 'lf_record_creacion_perfil_step_v1' in runtime,
    "router_owns_operation": 'String(ex.operation_code' in runtime and 'PROFILE_OPERATIONS' in runtime,
    "dynamic_contracts": 'lf_operation_step_contracts?operation_code=eq.' in runtime,
    "dynamic_judges": 'lf_operation_step_judge_bindings?operation_code=eq.' in runtime,
    "dynamic_policies": 'v_lf_operation_policy_snapshot?operation_code=eq.' in runtime,
    "batch_missing_evidence_fails": 'PROFILE_OPERATION_BATCH_STEP_INVALID' in batch and '!evidenceRef' in batch and '!evidencePayload' in batch,
    "batch_duplicate_fails": 'PROFILE_OPERATION_BATCH_DUPLICATE_STEP' in batch,
    "batch_empty_fails": 'PROFILE_OPERATION_BATCH_EMPTY' in batch,
    "batch_transport_limit_is_not_business_step_count": 'MAX_SAFE_TRANSPORT_STEPS = 64' in batch and 'MAX_BATCH_STEPS = 40' not in batch,
    "workflow_source_only_dispatch": 'source_canary_only' in workflow and 'NON_CANARY_PROFILE_CREATION_EXECUTED=false' in workflow,
    "workflow_router_source_gate": 'ROUTER_REQUIRES_SUPABASE_EVIDENCE_REF' in workflow and 'ROUTER_READ_REQUIRED' in workflow,
    "workflow_step_envelope_gate": 'MISSING_STEP_RESULT' in workflow and 'MISSING_BLOCKING_CODES' in workflow,
    # Required fail-closed negative surface from EKB PROFILE-CREATOR-CONTINUATION-SOURCE-TEST-004.
    "negative_unauthorized_caller": all(code in caller for code in ['OIDC_TOKEN_INVALID', 'OIDC_REPOSITORY_MISMATCH', 'OIDC_REF_MISMATCH', 'OIDC_WORKFLOW_MISMATCH']),
    "negative_wrong_execution_identity": 'PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH' in runtime and 'STEP_EXECUTION_IDENTITY_MISMATCH' in runtime,
    "negative_prior_step_not_clean": 'PRIOR_REQUIRED_STEP_NOT_CLEAN' in recorder,
    "negative_required_evidence_missing": 'REQUIRED_EVIDENCE_MISSING' in recorder,
    "negative_blocked_evidence": 'BLOCKING_CODES_INVALID' in recorder and "jsonb_array_length(v_blocking_codes)>0" in recorder,
    "negative_replay_different_evidence": 'STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE' in recorder,
    "negative_stale_batch_cursor": 'PROFILE_OPERATION_BATCH_STEP_NOT_CURRENT' in caller and 'expected_step_id: expectedStepId' in caller,
    "negative_update_no_unproven_recorder": 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in runtime,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit(f"FAIL_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE:{','.join(failed)}")
print(f"PASS_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE={sum(checks.values())}/{len(checks)}")
