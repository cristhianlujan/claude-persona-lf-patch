from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
CALLER = ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts"
BATCH = ROOT / "supabase/functions/lf-profile-creator-governance-caller-v1/batch.ts"
RUNTIME = ROOT / "supabase/functions/run-creacion-perfil-lf/index.ts"
WORKFLOW = ROOT / ".github/workflows/lf-customer-profile-creator-governance-caller.yml"
EXACT_TARGET = ROOT / "skills/profile_creator/contracts/existing_artifact_remediation_contract.json"
JUDGE_BINDING = ROOT / "skills/profile_creator/contracts/update_judge_semantics_contract.json"
UI_SKILL = ROOT / "profiles/ui_architect/SKILL.md"

caller = CALLER.read_text(encoding="utf-8")
batch = BATCH.read_text(encoding="utf-8")
runtime = RUNTIME.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")
exact_target = json.loads(EXACT_TARGET.read_text(encoding="utf-8"))
judge_binding = json.loads(JUDGE_BINDING.read_text(encoding="utf-8"))
ui_skill = UI_SKILL.read_text(encoding="utf-8")
judge_source = ROOT / judge_binding['source_ref']
judge_source_sha = hashlib.sha256(judge_source.read_bytes()).hexdigest() if judge_source.is_file() else None

blocking = set(exact_target.get('fail_closed', {}).get('blocking_conditions', []))
required_negative = {
    'EXECUTION_NOT_BOUND_TO_TARGET','MISSING_BOUND_REVISION','BOUND_REVISION_NOT_STRUCTURED',
    'TARGET_IDENTITY_MISMATCH','REVISION_MISMATCH','STALE_REVISION_WITHOUT_REREAD',
    'STALE_REVISION_WITHOUT_REBIND','RASTER_ARTIFACT_MISMATCH','RASTER_SHA_MISMATCH',
    'RASTER_DIMENSIONS_MISMATCH','MISSING_AUTHORIZED_DELTA_FOR_REMEDIATE_EXISTING',
    'SHELL_RECEIPT_MISSING_WHEN_APPLICABLE','SHELL_RECEIPT_BOUND_REVISION_MISMATCH',
    'OPERATION_OUTSIDE_AUTHORIZED_DELTA','SHELL_LOCKED_MUTATION','OUTSIDE_DELTA_MUTATION',
    'PROFILE_SELF_AUTHORIZES_DOWNSTREAM'
}
required_binding = set(exact_target.get('required_pre_write_evidence', []))

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

    # Exact-target binding is a seam repair in the existing UPDATE pre-write gate.
    "exact_target_update_scope": exact_target.get('operation_code') == 'ACTUALIZACION_PERFIL_LF',
    "exact_target_reuses_prewrite": exact_target.get('step_id') == 'pre_write_execution_binding_gate',
    "exact_target_no_new_layer_step_ddl": all(exact_target.get('architecture', {}).get(k) is False for k in ['new_layer','new_table','new_step','ddl_required']),
    "exact_target_binding_fields": {'execution_bound_to_target_before_change','bound_revision'} <= required_binding,
    "exact_target_no_free_text_revision": exact_target.get('revision_continuity', {}).get('free_text_write_plan_is_not_revision_evidence') is True,
    "exact_target_stale_rebind": exact_target.get('revision_continuity', {}).get('stale_revision_requires_reread') is True and exact_target.get('revision_continuity', {}).get('stale_revision_requires_explicit_rebind') is True,
    "exact_target_fail_closed": exact_target.get('fail_closed', {}).get('downstream_authorized') is False and exact_target.get('fail_closed', {}).get('executable_write_allowed') is False,
    "exact_target_negatives_complete": blocking == required_negative,
    "exact_target_same_sha_quality": exact_target.get('quality_pack_postconditions', {}).get('source_sha_match') is True,
    "exact_target_zero_outside_delta": exact_target.get('quality_pack_postconditions', {}).get('outside_authorized_delta_changes') == 0,
    "exact_target_zero_shell_locked": exact_target.get('quality_pack_postconditions', {}).get('shell_locked_mutations') == 0,
    "exact_target_shell_same_bound_revision": exact_target.get('existing_raster_extension', {}).get('shell_receipt_must_bind_same_bound_revision') is True,
    "exact_target_adapter_count_insufficient": exact_target.get('existing_raster_extension', {}).get('adapter_invocations_count_is_sufficient') is False,
    "exact_target_transversal_not_ui_copy": exact_target.get('policy_resolution', {}).get('do_not_copy_into_profile') is True and all(token not in ui_skill for token in ['bound_revision','execution_bound_to_target_before_change','shell_locked_zones','downstream_authorized']),
    "judge_source_exists": judge_source.is_file(),
    "judge_source_digest_exact": judge_source_sha == judge_binding.get('judge_sha'),
    "judge_pass_fail_material": bool(judge_binding.get('pass_if')) and bool(judge_binding.get('fail_if')),
    "judge_not_runtime_authority": judge_binding.get('runtime_activation_authorized') is False and judge_binding.get('canonical_update_recorder_authorized') is False,

    # Branch-local fail-closed surface.
    "negative_unauthorized_caller": all(code in caller for code in ['OIDC_TOKEN_INVALID', 'OIDC_REPOSITORY_MISMATCH', 'OIDC_REF_MISMATCH', 'OIDC_WORKFLOW_MISMATCH']),
    "negative_wrong_execution_identity": 'PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH' in runtime and 'STEP_EXECUTION_IDENTITY_MISMATCH' in runtime,
    "negative_missing_batch_evidence": 'PROFILE_OPERATION_BATCH_STEP_INVALID' in batch and '!evidenceRef' in batch and '!evidencePayload' in batch,
    "negative_duplicate_batch_step": 'PROFILE_OPERATION_BATCH_DUPLICATE_STEP' in batch,
    "negative_empty_batch": 'PROFILE_OPERATION_BATCH_EMPTY' in batch,
    "negative_stale_batch_cursor": 'PROFILE_OPERATION_BATCH_STEP_NOT_CURRENT' in caller and 'expected_step_id: expectedStepId' in caller,
    "negative_update_no_unproven_recorder": 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in runtime,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit(f"FAIL_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE:{','.join(failed)}")
print(f"PASS_PROFILE_CREATOR_CUSTOMER_CALLER_SOURCE={sum(checks.values())}/{len(checks)}")
