#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'supabase/migrations/20260903173500_actualizacion_perfil_canonical_step_recorder_v1.sql'
RUNTIME = ROOT / 'supabase/functions/run-creacion-perfil-lf/index.ts'

sql = MIGRATION.read_text(encoding='utf-8')
runtime = RUNTIME.read_text(encoding='utf-8')

checks = {
    'canonical_function_present': 'lf_record_actualizacion_perfil_step_v1' in sql,
    'operation_exact': "operation_code <> 'ACTUALIZACION_PERFIL_LF'" in sql,
    'target_type_exact': "target_type <> 'PERFIL'" in sql,
    'row_lock': 'for update' in sql.lower(),
    'actor_same_execution': 'ACTOR_EXECUTION_MUST_MATCH_TARGET_EXECUTION' in sql,
    'active_contract_required': "status='ACTIVE_ENFORCEMENT'" in sql,
    'source_bound_judge_required': 'SOURCE_BOUND_JUDGE_NOT_READY' in sql,
    'exact_judge_sha_bound': 'bef12f5dd3c08db63b92faf64f77703acf9172288dc0547e0de56241d1521557' in sql,
    'pass_fail_nonempty_not_fixed_count': "jsonb_array_length(v_judge.pass_if)=0" in sql and "jsonb_array_length(v_judge.fail_if)=0" in sql,
    'no_fixed_8_9_cardinality': 'jsonb_array_length(v_judge.pass_if)<>8' not in sql and 'jsonb_array_length(v_judge.fail_if)<>9' not in sql,
    'prior_clean_gate': 'PRIOR_REQUIRED_STEP_NOT_CLEAN' in sql,
    'required_evidence_gate': 'REQUIRED_EVIDENCE_MISSING' in sql,
    'blocking_codes_gate': 'BLOCKING_CODES_INVALID' in sql,
    'target_identity_gate': 'TARGET_IDENTITY_MISMATCH' in sql,
    'binding_gate': 'EXECUTION_NOT_BOUND_TO_TARGET' in sql,
    'structured_bound_revision': 'BOUND_REVISION_NOT_STRUCTURED' in sql,
    'current_revision_required': 'CURRENT_RESOLVED_REVISION_NOT_STRUCTURED' in sql,
    'revision_match': 'REVISION_MISMATCH' in sql,
    'stale_reread_negative': 'STALE_REVISION_WITHOUT_REREAD' in sql,
    'stale_rebind_negative': 'STALE_REVISION_WITHOUT_REBIND' in sql,
    'raster_exact_identity': 'RASTER_EXACT_IDENTITY_MISSING' in sql,
    'shell_same_revision': 'SHELL_RECEIPT_BOUND_REVISION_MISMATCH' in sql,
    'authorized_delta': 'MISSING_AUTHORIZED_DELTA_FOR_REMEDIATE_EXISTING' in sql,
    'outside_delta_blocked': 'OUTSIDE_DELTA_MUTATION' in sql,
    'shell_locked_blocked': 'SHELL_LOCKED_MUTATION' in sql,
    'github_write_identity': 'BLOCKED_GITHUB_WRITE_NOT_CLEAN' in sql,
    'github_readback_identity': 'BLOCKED_GITHUB_READBACK_NOT_CLEAN' in sql,
    'deterministic_before_semantic_contract': sql.index("p_step_id='deterministic_validation'") < sql.index("p_step_id='semantic_judge'"),
    'close_keeps_report_output_possible': "p_step_id='close'" in sql and "'next_gate','report_output'" in sql,
    'final_status_after_report': "p_step_id='report_output'" in sql and "set status='COMPLETED'" in sql,
    'transactional_insert': 'insert into public.lf_operation_execution_steps' in sql,
    'rollback_on_close_failure': 'raise exception' in sql,
    'runtime_still_fail_closed_until_wired': 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in runtime,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_UPDATE_PROFILE_CANONICAL_RECORDER_SOURCE:' + ','.join(failed))
print(f'PASS_UPDATE_PROFILE_CANONICAL_RECORDER_SOURCE={sum(checks.values())}/{len(checks)}')
