#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = (ROOT / 'supabase/functions/run-creacion-perfil-lf/index.ts').read_text(encoding='utf-8')
SEMANTICS = ROOT / 'skills/profile_creator/contracts/update_judge_semantics_contract.json'
RECORDER = ROOT / 'supabase/migrations/20260903173500_actualizacion_perfil_canonical_step_recorder_v1.sql'

# Source materialization and runtime activation are intentionally separate gates.
# This test allows a recorder candidate to exist while UPDATE runtime writes remain
# fail-closed until exact-head validation and controlled DB materialization/readback.
checks = {
    'recorder_source_present': RECORDER.is_file(),
    'update_runtime_still_fails_closed': 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in RUNTIME,
    'runtime_not_yet_calling_update_rpc': 'rpc("lf_record_actualizacion_perfil_step_v1"' not in RUNTIME,
    'no_runtime_activation_claim': 'UPDATE_JUDGE_SEMANTICS_CONTRACT_READY' not in RUNTIME,
}

if RECORDER.exists():
    recorder = RECORDER.read_text(encoding='utf-8')
    checks.update({
        'canonical_update_rpc_declared': 'lf_record_actualizacion_perfil_step_v1' in recorder,
        'recorder_operation_exact': "operation_code <> 'ACTUALIZACION_PERFIL_LF'" in recorder,
        'recorder_source_bound_judge_gate': 'SOURCE_BOUND_JUDGE_NOT_READY' in recorder,
        'recorder_exact_target_binding_gate': 'EXECUTION_NOT_BOUND_TO_TARGET' in recorder and 'REVISION_MISMATCH' in recorder,
        'recorder_stale_rebind_gate': 'STALE_REVISION_WITHOUT_REREAD' in recorder and 'STALE_REVISION_WITHOUT_REBIND' in recorder,
        'recorder_shell_same_revision_gate': 'SHELL_RECEIPT_BOUND_REVISION_MISMATCH' in recorder,
        'recorder_authorized_delta_gate': 'MISSING_AUTHORIZED_DELTA_FOR_REMEDIATE_EXISTING' in recorder,
        'recorder_no_fixed_rule_cardinality': 'pass_if)<>8' not in recorder and 'fail_if)<>9' not in recorder,
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
        'exact_target_pass_semantics': all(x in pass_if for x in [
            'execution_bound_to_target_before_change_is_true',
            'bound_revision_matches_current_resolved_revision',
            'stale_revision_has_reread_and_explicit_rebind_when_applicable',
        ]),
        'exact_target_fail_semantics': all(x in fail_if for x in [
            'execution_binding_missing_or_false',
            'bound_revision_mismatch',
            'stale_revision_without_explicit_rebind',
        ]),
        'declared_not_observed': data.get('declared_evidence_is_observed_evidence') is False,
        'runtime_not_authorized': data.get('runtime_activation_authorized') is False,
        'recorder_contract_not_self_authorized': data.get('canonical_update_recorder_authorized') is False,
    })

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_UPDATE_RECORDER_READINESS:' + ','.join(failed))
print(f'PASS_UPDATE_RECORDER_READINESS={sum(checks.values())}/{len(checks)}')
print('RECORDER_SOURCE_READY=true')
print('RUNTIME_UPDATE_WRITE_ENABLED=false')
