#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
RUNTIME=(ROOT/'supabase/functions/run-creacion-perfil-lf/index.ts').read_text(encoding='utf-8')
COMMON=(ROOT/'skills/profile_creator/contracts/profile_operation_common_recorder_v1.sql').read_text(encoding='utf-8')
SEMANTICS=ROOT/'skills/profile_creator/contracts/update_judge_semantics_contract.json'
CREATE_RECORDER=ROOT/'supabase/migrations/20260902233217_profile_creator_step_status_contract_fix.sql'
ENFORCEMENT=ROOT/'supabase/migrations/20260831062847_fix_operation_judge_jsonb_shape_compatibility.sql'
checks={
 'update_runtime_uses_server_trust':'v22-profile-update-server-trust-context' in RUNTIME,
 'old_update_block_removed':'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' not in RUNTIME,
 'no_parallel_update_rpc':'lf_record_actualizacion_perfil_step_v1' not in RUNTIME and 'lf_record_actualizacion_perfil_step_v1' not in COMMON,
 'common_recorder_used':'lf_record_profile_operation_step_v1' in RUNTIME and 'lf_record_profile_operation_step_v1' in COMMON,
 'server_context_required':'server_trust_context_valid' in COMMON and 'GITHUB_PUBLIC_API_EXACT_REF_V1' in COMMON,
 'caller_trust_stripped':'stripCallerTrust' in RUNTIME,
 'create_recorder_source_present':CREATE_RECORDER.is_file(),
 'operation_neutral_enforcement_source_present':ENFORCEMENT.is_file(),
}
if ENFORCEMENT.exists():
 e=ENFORCEMENT.read_text(encoding='utf-8'); checks.update({'shared_trigger_function_known':'lf_prod_enforcement_step_gate_v01' in e,'shared_binding_resolution':'lf_operation_step_judge_bindings' in e,'shared_required_evidence_gate':'required_evidence_keys' in e})
if SEMANTICS.exists():
 data=json.loads(SEMANTICS.read_text(encoding='utf-8')); source_ref=data.get('source_ref'); source_path=ROOT/source_ref if isinstance(source_ref,str) else None; source_exists=bool(source_path and source_path.is_file()); source_sha=hashlib.sha256(source_path.read_bytes()).hexdigest() if source_exists else None
 checks.update({'operation_exact':data.get('operation_code')=='ACTUALIZACION_PERFIL_LF','source_exists':source_exists,'judge_sha_matches_source':source_sha==data.get('judge_sha'),'declared_not_observed':data.get('declared_evidence_is_observed_evidence') is False})
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL_UPDATE_RECORDER_READINESS:'+','.join(failed))
print(f'PASS_UPDATE_RECORDER_READINESS={sum(checks.values())}/{len(checks)}')
print('RECORDER_REBASELINE=COMMON_RECORDER_SERVER_TRUST_CONTEXT')
print('RUNTIME_UPDATE_PREWRITE_SOURCE_ENABLED=true')
