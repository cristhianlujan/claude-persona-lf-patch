#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CALLER = (ROOT / 'supabase/functions/lf-profile-creator-governance-caller-v1/index.ts').read_text(encoding='utf-8')
BATCH = (ROOT / 'supabase/functions/lf-profile-creator-governance-caller-v1/batch.ts').read_text(encoding='utf-8')
RUNTIME = (ROOT / 'supabase/functions/run-creacion-perfil-lf/index.ts').read_text(encoding='utf-8')

checks = {
    'generic_next_step_action': 'profile_operation_next_step_v1' in CALLER and 'next_profile_operation_step_v1' in RUNTIME,
    'generic_batch_action': 'profile_operation_record_batch_v1' in CALLER,
    'generic_step_action': 'profile_operation_record_step_v1' in CALLER and 'record_profile_operation_step_v1' in RUNTIME,
    'router_owned_operation_from_execution': 'String(ex.operation_code' in RUNTIME,
    'supports_create': 'CREACION_PERFIL_LF' in RUNTIME,
    'supports_update': 'ACTUALIZACION_PERFIL_LF' in RUNTIME,
    'dynamic_step_contracts': 'lf_operation_step_contracts?operation_code=eq.' in RUNTIME,
    'dynamic_step_judges': 'lf_operation_step_judge_bindings?operation_code=eq.' in RUNTIME,
    'dynamic_policies': 'v_lf_operation_policy_snapshot?operation_code=eq.' in RUNTIME,
    'currentness_before_batch_write': 'expectedStepId !== step.step_id' in CALLER,
    'currentness_inside_runtime': 'PROFILE_OPERATION_STEP_NOT_CURRENT' in RUNTIME,
    'creation_recorder_reused': 'lf_record_creacion_perfil_step_v1' in RUNTIME,
    'update_fails_closed_without_canonical_recorder': 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in RUNTIME,
    'no_direct_db_step_write_in_caller': 'lf_operation_execution_steps' not in CALLER and '.from(' not in CALLER,
    'no_business_count_40_hardcode': 'MAX_BATCH_STEPS = 40' not in BATCH and 'MAX_BATCH_STEPS=40' not in BATCH,
    'transport_bound_not_business_flow': 'MAX_SAFE_TRANSPORT_STEPS = 64' in BATCH,
    'rejects_empty': 'PROFILE_OPERATION_BATCH_EMPTY' in BATCH,
    'rejects_duplicate_step': 'PROFILE_OPERATION_BATCH_DUPLICATE_STEP' in BATCH,
    'requires_evidence_ref': '!evidenceRef' in BATCH,
    'requires_evidence_payload': '!evidencePayload' in BATCH,
    'exclusive_execution_origin': 'AUTOMATION_PROFILE_CREATOR_DUAL_EXECUTOR' in CALLER,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_PROFILE_OPERATION_GENERIC_RESUMER:' + ','.join(failed))
print(f'PASS_PROFILE_OPERATION_GENERIC_RESUMER={sum(checks.values())}/{len(checks)}')
