#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = (ROOT / 'supabase/functions/run-creacion-perfil-lf/index.ts').read_text(encoding='utf-8')
SEMANTICS = ROOT / 'skills/profile_creator/contracts/update_judge_semantics_contract.json'
CREATE_RECORDER = ROOT / 'supabase/migrations/20260902233217_profile_creator_step_status_contract_fix.sql'
ENFORCEMENT = ROOT / 'supabase/migrations/20260831062847_fix_operation_judge_jsonb_shape_compatibility.sql'

# Rebaseline: do not add a parallel UPDATE recorder. Existing DB enforcement is
# already operation-neutral at the execution_steps boundary. The next recorder
# change must reuse/generalize the existing recorder path and preserve fail-closed
# UPDATE runtime until durable negative/positive tests are ready.
checks = {
    'update_runtime_still_fails_closed': 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in RUNTIME,
    'no_parallel_update_rpc_call': 'rpc("lf_record_actualizacion_perfil_step_v1"' not in RUNTIME,
    'no_parallel_update_recorder_source': not any(ROOT.glob('supabase/migrations/*actualizacion_perfil_canonical_step_recorder*.sql')),
    'create_recorder_source_present': CREATE_RECORDER.is_file(),
    'operation_neutral_enforcement_source_present': ENFORCEMENT.is_file(),
}

if CREATE_RECORDER.exists():
    create_recorder = CREATE_RECORDER.read_text(encoding='utf-8')
    checks.update({
        'existing_recorder_known': 'lf_record_creacion_perfil_step_v1' in create_recorder,
        'existing_recorder_transactional_insert': 'insert into public.lf_operation_execution_steps' in create_recorder.lower(),
    })

if ENFORCEMENT.exists():
    enforcement = ENFORCEMENT.read_text(encoding='utf-8')
    checks.update({
        'shared_trigger_function_known': 'lf_prod_enforcement_step_gate_v01' in enforcement,
        'shared_binding_resolution': 'lf_operation_step_judge_bindings' in enforcement,
        'shared_required_evidence_gate': 'required_evidence_keys' in enforcement,
        'shared_canonical_step_gate': 'lf_operation_steps' in enforcement,
    })

if SEMANTICS.exists():
    data = json.loads(SEMANTICS.read_text(encoding='utf-8'))
    source_ref = data.get('source_ref')
    source_path = ROOT / source_ref if isinstance(source_ref, str) else None
    source_exists = bool(source_path and source_path.is_file())
    source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest() if source_exists else None
    pass_if = data.get('pass_if')
    fail_if = data.get('fail_if')
    checks.update({
        'operation_exact': data.get('operation_code') == 'ACTUALIZACION_PERFIL_LF',
        'step_reuses_prewrite': data.get('step_id') == 'pre_write_execution_binding_gate',
        'judge_code_exact': data.get('judge_code') == 'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1',
        'source_ref_present': isinstance(source_ref, str) and bool(source_ref.strip()),
        'source_exists': source_exists,
        'judge_sha_present': isinstance(data.get('judge_sha'), str) and len(data.get('judge_sha')) == 64,
        'judge_sha_matches_source': source_sha == data.get('judge_sha'),
        'pass_if_nonempty': isinstance(pass_if, list) and len(pass_if) > 0,
        'fail_if_nonempty': isinstance(fail_if, list) and len(fail_if) > 0,
        'exact_target_pass_semantics_declared': all(x in pass_if for x in [
            'execution_bound_to_target_before_change_is_true',
            'bound_revision_matches_current_resolved_revision',
            'stale_revision_has_reread_and_explicit_rebind_when_applicable',
        ]),
        'exact_target_fail_semantics_declared': all(x in fail_if for x in [
            'execution_binding_missing_or_false',
            'bound_revision_mismatch',
            'stale_revision_without_explicit_rebind',
        ]),
        'declared_not_observed': data.get('declared_evidence_is_observed_evidence') is False,
        'runtime_not_authorized': data.get('runtime_activation_authorized') is False,
        'recorder_not_self_authorized': data.get('canonical_update_recorder_authorized') is False,
    })

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_UPDATE_RECORDER_READINESS:' + ','.join(failed))
print(f'PASS_UPDATE_RECORDER_READINESS={sum(checks.values())}/{len(checks)}')
print('RECORDER_REBASELINE=SHARED_ENFORCEMENT_EXISTING_RECORDER_GENERALIZATION')
print('RUNTIME_UPDATE_WRITE_ENABLED=false')
