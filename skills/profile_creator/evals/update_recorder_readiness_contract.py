#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = (ROOT / 'supabase/functions/run-creacion-perfil-lf/index.ts').read_text(encoding='utf-8')
SEMANTICS = ROOT / 'skills/profile_creator/contracts/update_judge_semantics_contract.json'

# UPDATE writes must remain fail-closed until a source-bound judge semantics
# contract exists. Required-evidence-key presence alone is not semantic judgment.
if not SEMANTICS.exists():
    checks = {
        'update_write_fails_closed': 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' in RUNTIME,
        'no_update_specific_rpc_call': 'lf_record_actualizacion_perfil_step_v1' not in RUNTIME,
        'no_claimed_update_semantics_contract': 'UPDATE_JUDGE_SEMANTICS_CONTRACT_READY' not in RUNTIME,
    }
else:
    data = json.loads(SEMANTICS.read_text(encoding='utf-8'))
    pass_if = data.get('pass_if')
    fail_if = data.get('fail_if')
    checks = {
        'operation_exact': data.get('operation_code') == 'ACTUALIZACION_PERFIL_LF',
        'judge_code_present': isinstance(data.get('judge_code'), str) and bool(data.get('judge_code').strip()),
        'judge_sha_present': isinstance(data.get('judge_sha'), str) and len(data.get('judge_sha')) == 64,
        'pass_if_nonempty': isinstance(pass_if, list) and len(pass_if) > 0,
        'fail_if_nonempty': isinstance(fail_if, list) and len(fail_if) > 0,
        'source_ref_present': isinstance(data.get('source_ref'), str) and bool(data.get('source_ref').strip()),
        'observed_evidence_required': data.get('declared_evidence_is_observed_evidence') is False,
    }

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_UPDATE_RECORDER_READINESS:' + ','.join(failed))
print(f'PASS_UPDATE_RECORDER_READINESS={sum(checks.values())}/{len(checks)}')
