#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CALLER = (ROOT / 'supabase/functions/lf-profile-creator-governance-caller-v1/index.ts').read_text(encoding='utf-8')
BATCH = (ROOT / 'supabase/functions/lf-profile-creator-governance-caller-v1/batch.ts').read_text(encoding='utf-8')

checks = {
    'batch_action_present': 'profile_creator_record_batch_v1' in CALLER,
    'reuses_existing_runtime_step_action': 'action: "record_profile_creation_step_v1"' in CALLER,
    'stops_on_first_block': 'BATCH_BLOCKED' in BATCH and 'result.outcome !== "STEP_RECORDED"' in CALLER,
    'bounded_batch': 'MAX_BATCH_STEPS = 40' in BATCH,
    'rejects_empty': 'PROFILE_CREATOR_BATCH_EMPTY' in BATCH,
    'rejects_oversize': 'PROFILE_CREATOR_BATCH_TOO_LARGE' in BATCH,
    'rejects_duplicate_step': 'PROFILE_CREATOR_BATCH_DUPLICATE_STEP' in BATCH,
    'requires_evidence_ref': '!evidenceRef' in BATCH,
    'requires_evidence_payload': '!evidencePayload' in BATCH,
    'no_direct_db_step_write': 'lf_operation_execution_steps' not in CALLER and '.from(' not in CALLER,
    'no_runtime_deploy_authority': 'runtime_enabled' not in CALLER,
    'continuation_origin': 'AUTOMATION_AGENTE_PROFILE_CREATOR_CUSTOMER_CONTINUACION' in CALLER,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_PROFILE_CREATOR_BATCH_RESUME:' + ','.join(failed))
print(f'PASS_PROFILE_CREATOR_BATCH_RESUME={sum(checks.values())}/{len(checks)}')
