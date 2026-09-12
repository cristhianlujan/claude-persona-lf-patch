from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
C=json.loads((ROOT/'contracts/profile_operation_blocked_evidence_v1.json').read_text())
SQL=(ROOT/'contracts/profile_operation_common_recorder_v1.sql').read_text()
MIGRATION=(ROOT.parents[1]/'supabase/migrations/20260903205327_lf_profile_operation_common_recorder_v1.sql').read_text()
checks={
 'no_new_table':C['architecture']['new_table'] is False,
 'no_new_layer':C['architecture']['new_layer'] is False,
 'existing_step_table':C['architecture']['persistence']=='lf_operation_execution_steps',
 'common_recorder_only':C['architecture']['recorder']=='lf_record_profile_operation_step_v1',
 'durable_after_binding':C['identity_boundary']['durable_only_after'][-1]=='active_binding_resolved',
 'create_contract_active':C['contract_status_resolution']['CREACION_PERFIL_LF']=='ACTIVE',
 'update_contract_active':C['contract_status_resolution']['ACTUALIZACION_PERFIL_LF']=='ACTIVE_ENFORCEMENT',
 'blocked_status_derived':C['durable_blocked_path']['status']=='binding.blocked_result_value',
 'attempt_history_present':'attempt_history' in C['durable_blocked_path']['required_payload_extensions'],
 'caller_not_authority':C['durable_blocked_path']['caller_status_is_authority'] is False,
 'audit_non_null':C['audit_semantics']['key_presence_alone_is_proof'] is False and "<> 'null'::jsonb" in C['audit_semantics']['minimum_non_null_predicate'],
 'retry_same_row':C['retry_semantics']['same_execution_step_row'] is True and C['retry_semantics']['blocked_row_is_terminal'] is False,
 'preserve_history':C['retry_semantics']['previous_attempt_preserved_in_attempt_history'] is True,
 'server_trust_block_known':'PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED' in C['durable_block_codes'],
 'live_materialized':C['activation']['live_materialized'] is True,
 'service_role_only':C['activation']['live_execute_roles']==['service_role'] and C['activation']['anon_execute'] is False and C['activation']['authenticated_execute'] is False,
 'update_path_enabled':C['activation']['update_write_enabled'] is True and C['activation']['runtime_update_path_enabled'] is True,
 'positive_test_declared':'positive_server_trust_context_records_step60' in C['required_tests'],
 'caller_override_test_declared':'caller_trust_override_cannot_bypass_server_derivation' in C['required_tests'],
 'sql_retryable':'v_existing_retryable' in SQL,
 'sql_persists_blocked':'status=v_binding.blocked_result_value' in SQL and 'blocking_findings' in SQL,
 'sql_preserves_history':'attempt_history' in SQL,
 'sql_clean_retry':'Clean retry accepted transactionally' in SQL and 'status=v_binding.clean_result_value' in SQL,
 'sql_server_context':'server_trust_context_valid' in SQL and 'GITHUB_PUBLIC_API_EXACT_REF_V1' in SQL,
 'sql_fail_closed_code':'PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED' in SQL,
 'migration_service_role':'to service_role;' in MIGRATION,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL_PROFILE_OPERATION_BLOCKED_EVIDENCE:'+','.join(failed))
print(f'PASS_PROFILE_OPERATION_BLOCKED_EVIDENCE={sum(checks.values())}/{len(checks)}')
print('LIVE_MATERIALIZED=true')
print('LIVE_EXECUTE_SCOPE=service_role_only')
print('UPDATE_RUNTIME_PATH_SOURCE_ENABLED=true')
