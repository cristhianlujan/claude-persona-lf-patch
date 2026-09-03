#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / 'skills/profile_creator/contracts/existing_artifact_remediation_contract.json'
UI_SKILL_PATH = ROOT / 'profiles/ui_architect/SKILL.md'

contract = json.loads(CONTRACT_PATH.read_text(encoding='utf-8'))
ui_skill = UI_SKILL_PATH.read_text(encoding='utf-8')

required_all = set(contract.get('required_for_all_existing', []))
required_remediate = set(contract.get('required_for_remediate_existing', []))
blocking = set(contract.get('fail_closed', {}).get('blocking_conditions', []))
quality = contract.get('quality_pack_postconditions', {})
shell = contract.get('shell_receipt_rule', {})
policy = contract.get('policy_resolution', {})

expected_all = {
    'source_ref','source_image_sha256','source_dimensions','visual_evidence',
    'target_component_id','concrete_operation','canonical_component_or_token',
    'observable_acceptance_criteria'
}
expected_remediate = {'authorized_delta','editable_zones','shell_locked_zones'}
expected_negative = {
    'MISSING_SOURCE_REF','MISSING_SOURCE_SHA256','MISSING_SOURCE_DIMENSIONS','SOURCE_SHA_MISMATCH',
    'MISSING_VISUAL_EVIDENCE','MISSING_AUTHORIZED_DELTA_FOR_REMEDIATE_EXISTING',
    'SHELL_RECEIPT_MISSING_WHEN_APPLICABLE','SHELL_RECEIPT_SOURCE_MISMATCH',
    'SHELL_RECEIPT_SHA_MISMATCH','ADAPTER_INVOCATION_WITHOUT_EXACT_BINDING',
    'OPERATION_OUTSIDE_AUTHORIZED_DELTA','SHELL_LOCKED_MUTATION','OUTSIDE_DELTA_MUTATION',
    'PROFILE_SELF_AUTHORIZES_DOWNSTREAM'
}

checks = {
    'operation_is_update': contract.get('operation_code') == 'ACTUALIZACION_PERFIL_LF',
    'dedicated_step_id': contract.get('step_id') == 'existing_artifact_binding_gate',
    'evaluate_and_remediate_covered': set(contract.get('applies_when', [])) == {'EVALUATE_EXISTING','REMEDIATE_EXISTING'},
    'all_existing_fields_complete': required_all == expected_all,
    'remediate_fields_complete': required_remediate == expected_remediate,
    'shell_receipt_conditional': shell.get('required_when_shell_applies') is True,
    'shell_receipt_same_artifact': shell.get('must_bind_same_source_ref') is True,
    'shell_receipt_same_sha': shell.get('must_bind_same_source_sha256') is True,
    'adapter_count_not_receipt': shell.get('adapter_invocations_count_is_sufficient') is False,
    'fail_closed_downstream': contract.get('fail_closed', {}).get('downstream_authorized') is False,
    'fail_closed_no_executable_instructions': contract.get('fail_closed', {}).get('executable_instructions_allowed') is False,
    'negative_matrix_complete': blocking == expected_negative,
    'quality_same_sha': quality.get('source_sha_match') is True,
    'quality_outside_delta_zero': quality.get('outside_authorized_delta_changes') == 0,
    'quality_shell_locked_zero': quality.get('shell_locked_mutations') == 0,
    'quality_target_within_delta': quality.get('target_change_within_delta') is True,
    'quality_acceptance_observable': quality.get('observable_acceptance_met') is True,
    'source_policy_reused': policy.get('source_binding_policy') == 'POL-LF-SOURCE-RESOLUTION',
    'shell_policy_reused': policy.get('shell_binding_policy') == 'POL-LF-ACTIVATION-ROUTING',
    'transversal_not_profile_copy': policy.get('do_not_copy_into_profile') is True,
    'ui_profile_not_polluted_with_contract_fields': all(token not in ui_skill for token in ['source_image_sha256','shell_locked_zones','authorized_delta','downstream_authorized']),
    'no_auto_promotion': all(contract.get('lifecycle', {}).get(k) is False for k in ['runtime_promotion_authorized','production_authorized','validated_authorized']),
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL_EXISTING_ARTIFACT_REMEDIATION_CONTRACT:' + ','.join(failed))
print(f'PASS_EXISTING_ARTIFACT_REMEDIATION_CONTRACT={sum(checks.values())}/{len(checks)}')
