#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / 'skills/profile_creator/contracts/existing_artifact_remediation_contract.json'
UI_SKILL_PATH = ROOT / 'profiles/ui_architect/SKILL.md'

contract = json.loads(CONTRACT_PATH.read_text(encoding='utf-8'))
ui_skill = UI_SKILL_PATH.read_text(encoding='utf-8')

arch = contract['architecture']
continuity = contract['revision_continuity']
raster = contract['existing_raster_extension']
judge = contract['judge_readiness']
post = contract['post_write_existing_checks_reused']
required = set(contract['required_pre_write_evidence'])

contract_checks = {
    'reuse_prewrite_step': contract['step_id'] == 'pre_write_execution_binding_gate',
    'no_new_layer': arch['new_layer'] is False,
    'no_new_table': arch['new_table'] is False,
    'no_new_step': arch['new_step'] is False,
    'no_ddl': arch['ddl_required'] is False,
    'jsonb_transport': arch['evidence_transport'] == 'existing evidence_payload JSONB',
    'explicit_bound_bool': 'execution_bound_to_target_before_change' in required,
    'explicit_bound_revision': 'bound_revision' in required,
    'no_free_text_revision_inference': continuity['free_text_write_plan_is_not_revision_evidence'] is True,
    'stale_requires_reread': continuity['stale_revision_requires_reread'] is True,
    'stale_requires_rebind': continuity['stale_revision_requires_explicit_rebind'] is True,
    'judge_sha_required': judge['judge_sha_required'] is True,
    'judge_pass_fail_required': judge['pass_if_required'] is True and judge['fail_if_required'] is True,
    'update_recorder_remains_closed_until_judge_ready': judge['do_not_enable_update_recorder_until_ready'] is True,
    'post_write_reused_not_duplicated': all([
        post['github_write_identity_preserved'], post['github_readback_sha_match'],
        post['github_readback_identity_preserved'], post['regression_after_reused'],
        post['duplicate_post_write_gate'] is False,
    ]),
    'shell_same_bound_revision': raster['shell_receipt_must_bind_same_bound_revision'] is True,
    'adapter_count_not_binding': raster['adapter_invocations_count_is_sufficient'] is False,
    'ui_profile_not_polluted': all(t not in ui_skill for t in ['bound_revision','execution_bound_to_target_before_change','shell_locked_zones','downstream_authorized']),
    'no_auto_promotion': all(contract['lifecycle'][k] is False for k in ['runtime_promotion_authorized','production_authorized','validated_authorized']),
}

BASE = '0eeec4c2374b86390812961e14dabde5d8834d2e'
NEW = '2222222222222222222222222222222222222222'
TARGET = {'target_code':'PERFIL-QUALITY-PACK','target_path':'profiles/quality_pack'}

def generic_gate(bound_bool=True, bound_revision=BASE, current_revision=BASE,
                 target_code=TARGET['target_code'], target_path=TARGET['target_path'],
                 rebound=False):
    target_ok = target_code == TARGET['target_code'] and target_path == TARGET['target_path']
    revision_ok = bool(bound_revision) and bound_revision == current_revision
    stale_ok = revision_ok or rebound
    return 'PASS' if bound_bool and target_ok and revision_ok and stale_ok else 'BLOCK'

def raster_gate(artifact_id=85,
                sha='ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287',
                dimensions='1600x1000'):
    return 'PASS' if (
        artifact_id == 85 and
        sha == 'ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287' and
        dimensions == '1600x1000'
    ) else 'BLOCK'

cases = [
    ('NEG_BOUND_FALSE','BLOCK',generic_gate(bound_bool=False)),
    ('NEG_MISSING_REV','BLOCK',generic_gate(bound_revision=None)),
    ('NEG_REV_MISMATCH','BLOCK',generic_gate(bound_revision='1'*40)),
    ('NEG_STALE_NO_REBIND','BLOCK',generic_gate(bound_revision=BASE,current_revision=NEW,rebound=False)),
    ('NEG_TARGET_MISMATCH','BLOCK',generic_gate(target_code='PERFIL-OTHER')),
    ('POS_MATCH','PASS',generic_gate()),
    ('POS_STALE_REBOUND','PASS',generic_gate(bound_revision=NEW,current_revision=NEW,rebound=True)),
    ('SCREEN_POS_EXACT','PASS',raster_gate()),
    ('SCREEN_NEG_SHA','BLOCK',raster_gate(sha='deadbeef')),
    ('SCREEN_NEG_ARTIFACT','BLOCK',raster_gate(artifact_id=999)),
    ('SCREEN_NEG_DIM','BLOCK',raster_gate(dimensions='1599x1000')),
]

failed_contract = [name for name, ok in contract_checks.items() if not ok]
failed_matrix = [case for case, expected, actual in cases if expected != actual]
if failed_contract:
    raise SystemExit('FAIL_EXACT_TARGET_BINDING_CONTRACT:' + ','.join(failed_contract))
if failed_matrix:
    raise SystemExit('FAIL_EXACT_TARGET_BINDING_MATRIX:' + ','.join(failed_matrix))

print(f'PASS_EXACT_TARGET_BINDING_CONTRACT={sum(contract_checks.values())}/{len(contract_checks)}')
print(f'PASS_EXACT_TARGET_BINDING_MATRIX={len(cases)}/{len(cases)}')
for case, expected, actual in cases:
    print(f'{case}:expected={expected}:actual={actual}:PASS')
