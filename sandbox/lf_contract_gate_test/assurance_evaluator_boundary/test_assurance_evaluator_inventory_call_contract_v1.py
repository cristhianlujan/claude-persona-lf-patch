#!/usr/bin/env python3
import hashlib, json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
CONTRACT=HERE/'assurance_evaluator_call_contract_v1.json'
BOUNDARY=HERE/'assurance_evaluator_boundary_v1.json'
README=HERE/'README.md'
MIGRATION=ROOT/'supabase/migrations/20260930203100_lf_assurance_evaluator_inventory_wiring_v1.sql'

contract=json.loads(CONTRACT.read_text())
boundary=json.loads(BOUNDARY.read_text())
readme=README.read_text()
sql=MIGRATION.read_text()
sha=hashlib.sha256(CONTRACT.read_bytes()).hexdigest()

assert contract['capability_code']=='ASSURANCE_EVALUATOR'
assert contract['owner_scope']=='SUPER_ADMIN'
assert contract['canonical_entrypoint']['function']=='public.fn_lf_capability_bind_from_orchestrator_v1'
assert contract['canonical_entrypoint']['arguments_in_order']==[
 'p_execution_id','p_capability_code','p_expected_manifest_sha256','p_plan_digest','p_dispatch_receipt_id','p_actor_execution_id'
]
assert contract['forbidden_new_entry']['function']=='public.fn_lf_capability_bind_current_v1'
assert contract['forbidden_new_entry']['expected_decision']=='BLOCK_ORCHESTRATOR_ENTRY_GUARD_REQUIRED'
assert contract['current_expected_state']['capability_current_present'] is False
assert contract['current_expected_state']['active_subject_binding_count']==0
assert contract['current_expected_state']['valid_dispatch_before_promotion']=='BLOCK_NO_CURRENT_CAPABILITY'
assert boundary['invocation_contract']['ref'].endswith('assurance_evaluator_call_contract_v1.json')
assert boundary['invocation_contract']['canonical_entrypoint']=='public.fn_lf_capability_bind_from_orchestrator_v1'
assert '## Contrato canónico de invocación' in readme
assert "'ASSURANCE_EVALUATOR'" in readme
assert 'BLOCK_NO_CURRENT_CAPABILITY' in readme
for token in [
 'TRANSVERSAL_ASSURANCE_EVALUATOR',
 "'ACT-0001','GOBERNADO_POR'",
 "'CURRENTNESS_AUTHORITY','DEPENDE_DE'",
 "'ASSURANCE_COMPLETENESS','RELACIONADO_CAPACIDADES'",
 'public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)',
 sha,
]:
    assert token in sql, token
for forbidden in ['insert into public.lf_capability_current','fn_lf_capability_promote_v1(',"update public.lf_assurance_subject_bindings set status='active'"]:
    assert forbidden not in sql.lower(), forbidden
print(f'ASSURANCE_EVALUATOR_INVENTORY_CALL_CONTRACT_V1=PASS call_contract_sha256={sha}')
