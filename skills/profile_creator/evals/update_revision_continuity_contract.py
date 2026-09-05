from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
contract=json.loads((ROOT/'contracts/update_revision_continuity_contract.json').read_text())
runtime=(ROOT.parents[1]/'supabase/functions/run-creacion-perfil-lf/index.ts').read_text()
recorder=(ROOT/'contracts/profile_operation_common_recorder_v1.sql').read_text()
blocking=set(contract['blocking_codes'])
required={"PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED","PROFILE_UPDATE_BASELINE_REVISION_INVALID","PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED","PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED","PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED","PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED","PROFILE_UPDATE_STALE_REREAD_REQUIRED","PROFILE_UPDATE_STALE_REBIND_REQUIRED","PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH","PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH","PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED"}
checks={
 'update_scope':contract['operation_code']=='ACTUALIZACION_PERFIL_LF',
 'prewrite':contract['step_id']=='pre_write_execution_binding_gate',
 'no_new_architecture':all(contract['architecture'][k] is False for k in ['new_layer','new_table','new_step']),
 'baseline_persisted':contract['trusted_inputs']['baseline']['source']=='lf_operation_execution_steps.baseline_read.evidence_payload',
 'current_server':contract['trusted_inputs']['current']['source']=='GITHUB_PUBLIC_API_EXACT_REF_V1' and contract['trusted_inputs']['current']['current_resolver_location_today']=='run-creacion-perfil-lf',
 'blocking_complete':blocking==required,
 'server_authority_source':contract['server_authority_gate']['state']=='SOURCE_IMPLEMENTED',
 'recorder_accept_only_validated':contract['server_authority_gate']['recorder_behavior']=='ACCEPT_ONLY_VALIDATED_SERVER_CONTEXT',
 'runtime_v22':'v22-profile-update-server-trust-context' in runtime,
 'runtime_reads_baseline':'function baselineObservation' in runtime,
 'runtime_reads_main':'/git/ref/heads/main' in runtime,
 'runtime_reads_blob':'/contents/${encodedPath}?ref=${current}' in runtime,
 'runtime_strips_caller':'stripCallerTrust' in runtime,
 'runtime_bound_current':'PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH' in runtime,
 'runtime_stale_controls':all(x in runtime for x in ['PROFILE_UPDATE_STALE_REREAD_REQUIRED','PROFILE_UPDATE_STALE_REBIND_REQUIRED','PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH']),
 'runtime_injects_context':'server_trust_context_valid: true' in runtime,
 'recorder_validates_context':'server_trust_context_valid' in recorder and 'GITHUB_PUBLIC_API_EXACT_REF_V1' in recorder,
 'recorder_fail_closed_code':'PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED' in recorder,
 'activation_authorized':contract['activation']['update_recorder_enabled'] is True and contract['activation']['runtime_deployment_authorized'] is True and contract['activation']['production_authorized'] is True,
 'merge_false':contract['activation']['merge_authorized'] is False,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL_UPDATE_REVISION_CONTINUITY_CONTRACT:'+','.join(failed))
print(f'PASS_UPDATE_REVISION_CONTINUITY_CONTRACT={sum(checks.values())}/{len(checks)}')
print('SERVER_AUTHORITY_SOURCE_IMPLEMENTED=true')
print('UPDATE_PREWRITE_SOURCE_ENABLED=true')
