#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
TARGET=HERE/'pase_orchestrator_v1.py'

def load_target():
 spec=importlib.util.spec_from_file_location('pase_orchestrator_v1_test_target',TARGET)
 if spec is None or spec.loader is None: raise SystemExit('FAIL_PASE_ORCHESTRATOR_LOAD')
 module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def governance_admin(**overrides):
 value={'schema_version':'lf-ci-governance-admin-identity/v1','super_admin':'LF_GOVERNANCE','role':'SUPER_ADMIN_GOVERNANCE','status':'CANDIDATE_READ_ONLY','scope':'PASE_GOVERNANCE_ADMINISTRATION','applicability_authority':'CHANGESET_GOVERNANCE_LF_V1','orchestrator_consumer':'PASE_ORCHESTRATOR_V1','source_contract_schema_version':'lf-governance-super-admin/v1','source_revision':'a'*64,'binding_materialized':False,'supabase_registered':False}; value.update(overrides); return value

def plan(required, carrier_controls, *, coverage=True, admin=None, include_admin=True, **overrides):
 required=sorted(required)
 value={'schema_version':'lf-ci-execution-plan/v2','coverage_complete':coverage,'required_controls':required,'carrier_controls':carrier_controls,'plan_sha256':'b'*64,'applicability_sha256':'c'*64,'evidence_sha256':'d'*64,'base_sha':'1'*40,'head_sha':'2'*40,'authority_evidence_revision':'3'*40,'source_authority':{'resolved_revision':'3'*40,'decision':'MATCH'},'pase_control_enforcement':{'source_plan_sha256':'b'*64,'required_controls':required,'blocking_controls':[],'observe_only_controls':required,'policy_id':'PASE_CONTROL_REPAIR_QUARANTINE_V1','result_sha256':'e'*64}}
 if include_admin: value['governance_admin']=governance_admin() if admin is None else admin
 value.update(overrides); return value

def expect_error(module,payload,code,registry_path=None):
 try: module.build_dispatch_plan(payload,**({'registry_path':registry_path} if registry_path is not None else {}))
 except module.PaseOrchestratorError as exc: assert str(exc).startswith(code),(code,str(exc)); return
 raise AssertionError(f'expected {code}')

def main():
 module=load_target(); checks=0
 payload=plan(['DB_CANDIDATE_APPLY_ROLLBACK','MIGRATION_SOURCE_PARITY'],{'MIGRATION_SOURCE_PARITY':['MIGRATION_SOURCE_PARITY'],'LF_DB_REGRESSION':['DB_CANDIDATE_APPLY_ROLLBACK']})
 got=module.build_dispatch_plan(payload)
 assert [r['carrier'] for r in got['dispatches']]==['MIGRATION_SOURCE_PARITY','LF_DB_REGRESSION']
 assert got['applicability_authority']=='UPSTREAM_PLAN_ONLY' and got['execution_semantics']=='SEQUENTIAL_DELEGATION_ONLY'
 assert got['governance_admin']==payload['governance_admin'] and got['governance_admin']['binding_materialized'] is False
 assert got['no_owner_recalculation'] is True and got['no_per_control_owner_creation'] is True and got['no_parallel_authority'] is True
 assert got['execution_envelope_schema_version']=='lf-pase-execution-envelope/v1'
 envelope=got['execution_envelope']; assert envelope['writable_authority'] is False and envelope['plan_digest']==payload['plan_sha256'] and envelope['base_sha']==payload['base_sha'] and envelope['head_sha']==payload['head_sha'] and envelope['source_revision']==payload['authority_evidence_revision']
 assert got['dispatches'][1]['depends_on_carriers']==['MIGRATION_SOURCE_PARITY']
 assert got['dispatches'][0]['enforcement_modes']=={'MIGRATION_SOURCE_PARITY':'REPAIR_OBSERVE_ONLY'}
 assert all(len(r['execution_identity'])==64 and len(r['idempotency_key'])==64 for r in got['dispatches'])
 assert got==module.build_dispatch_plan(payload)
 checks+=1
 empty=plan([],{}); got=module.build_dispatch_plan(empty); assert got['dispatches']==[] and got['dispatch_count']==0 and got['control_count']==0; checks+=1
 expect_error(module,plan([],{},include_admin=False),'FAIL_PASE_GOVERNANCE_ADMIN_MISSING'); checks+=1
 expect_error(module,plan([],{},admin=governance_admin(schema_version='wrong')),'FAIL_PASE_GOVERNANCE_ADMIN_SCHEMA'); checks+=1
 expect_error(module,plan([],{},admin=governance_admin(super_admin='OTHER_ADMIN')),'FAIL_PASE_GOVERNANCE_ADMIN_IDENTITY'); checks+=1
 malformed=governance_admin(); del malformed['source_revision']; expect_error(module,plan([],{},admin=malformed),'FAIL_PASE_GOVERNANCE_ADMIN_STRUCTURE'); checks+=1
 expect_error(module,plan([],{},admin=governance_admin(source_revision='not-a-sha256')),'FAIL_PASE_GOVERNANCE_ADMIN_SOURCE_REVISION'); checks+=1
 expect_error(module,plan([],{},admin=governance_admin(binding_materialized='false')),'FAIL_PASE_GOVERNANCE_ADMIN_BINDING_MATERIALIZED'); checks+=1
 expect_error(module,plan([],{},admin=governance_admin(binding_materialized=True)),'BLOCK_PASE_BINDING_MATERIALIZED_UNSUPPORTED'); checks+=1
 expect_error(module,plan(['MIGRATION_SOURCE_PARITY','PROFILE_PACK'],{'MIGRATION_SOURCE_PARITY':['MIGRATION_SOURCE_PARITY']}),'FAIL_PASE_CARRIER_COVERAGE'); checks+=1
 expect_error(module,plan(['MIGRATION_SOURCE_PARITY'],{'MIGRATION_SOURCE_PARITY':['MIGRATION_SOURCE_PARITY'],'VALIDATE_LF_PACKS':['MIGRATION_SOURCE_PARITY']}),'FAIL_PASE_CONTROL_MULTI_CARRIER'); checks+=1
 expect_error(module,plan(['MIGRATION_SOURCE_PARITY'],{'LF_CONTRACT_CHECK':['MIGRATION_SOURCE_PARITY']}),'FAIL_PASE_CARRIER_DRIFT'); checks+=1
 expect_error(module,plan(['MIGRATION_SOURCE_PARITY'],{'MIGRATION_SOURCE_PARITY':['MIGRATION_SOURCE_PARITY']},coverage=False),'FAIL_PASE_PLAN_COVERAGE_INCOMPLETE'); checks+=1
 expect_error(module,plan([],{},base_sha=None),'FAIL_PASE_BASE_SHA'); checks+=1
 p=plan([],{}); p['source_authority']['resolved_revision']='4'*40; expect_error(module,p,'FAIL_PASE_SOURCE_REVISION_DRIFT'); checks+=1
 p=plan([],{}); p['pase_control_enforcement']['source_plan_sha256']='f'*64; expect_error(module,p,'FAIL_PASE_ENFORCEMENT_PLAN_DRIFT'); checks+=1
 p=plan(['MIGRATION_SOURCE_PARITY'],{'MIGRATION_SOURCE_PARITY':['MIGRATION_SOURCE_PARITY']}); p['pase_control_enforcement']['observe_only_controls']=[]; expect_error(module,p,'FAIL_PASE_ENFORCEMENT_PARTITION'); checks+=1
 with tempfile.TemporaryDirectory() as tmp:
  registry=Path(tmp)/'registry.json'; registry.write_text(json.dumps({'schema_version':'lf-ci-control-impact-registry/v2','controls':[{'control_id':'A','carrier':'CARRIER_A','dependencies':['B']},{'control_id':'B','carrier':'CARRIER_B','dependencies':['A']}]}))
  expect_error(module,plan(['A','B'],{'CARRIER_A':['A'],'CARRIER_B':['B']}),'FAIL_PASE_CARRIER_DEPENDENCY_CYCLE',registry)
 checks+=1
 source=TARGET.read_text(encoding='utf-8')
 for forbidden in ('import subprocess','import urllib','import requests','execute_sql','apply_migration','changed_paths','.classify(','validate_contract(','owner_runner','lf_governance_super_admin_contract_v1.json'):
  assert forbidden not in source,forbidden
 checks+=1
 print(f'PASS_PASE_ORCHESTRATOR_V1 checks={checks}'); return 0
if __name__=='__main__': raise SystemExit(main())
