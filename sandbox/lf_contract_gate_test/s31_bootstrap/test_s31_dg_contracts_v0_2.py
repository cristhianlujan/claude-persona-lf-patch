#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, importlib.util, json, sys
from pathlib import Path
from jsonschema import Draft7Validator

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('s31_dg_v02',ROOT/'validate_s31_dg_contracts_v0_2.py')
m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m)
RESOLVER=m.TrustedRefResolver(ROOT); HEAD=RESOLVER.head; TRUST=m.TRUSTED_RESOLVER_ID
EVIDENCE='sandbox/lf_contract_gate_test/s31_bootstrap/trusted_evidence'
POS=0; NEG=0

def load_json(n): return json.loads((ROOT/n).read_text())
def schema_errors(schema,value): return [e.message for e in sorted(Draft7Validator(schema).iter_errors(value),key=lambda e:list(e.path))]
def ref(name,revision=None): return f"github://{RESOLVER.repo}@{revision or HEAD}/{EVIDENCE}/{name}"
def obs(name): return RESOLVER.resolve(ref(name))
def binding(name):
 o=obs(name); return {'ref':ref(name),'sha256':o['sha256'],'resolver_id':TRUST}
def sha(name): return obs(name)['sha256']
def canonical(v): return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

D_SCHEMA=load_json('lf_shared_authority_typed_context_v0_2_candidate.schema.json')
E_SCHEMA=load_json('lf_capability_manifest_v0_3_candidate.schema.json')
F_SCHEMA=load_json('lf_common_evidence_envelope_v0_3_candidate.schema.json')
G_REQUEST_SCHEMA=load_json('lf_runtime_execution_port_v0_1_candidate.schema.json')
G_OUTPUT_SCHEMA=load_json('lf_runtime_execution_output_v0_1_candidate.schema.json')
E_INVENTORY=load_json('s31_e_capability_registry_gap_inventory_v0_2.json')
for x in [D_SCHEMA,E_SCHEMA,F_SCHEMA,G_REQUEST_SCHEMA,G_OUTPUT_SCHEMA]: Draft7Validator.check_schema(x)

def d_base():
 return {
  'schema':'lf-shared-governed-typed-context/v0.2-candidate','producer_id':'S31_D_PRODUCER','current_run_id':'run-001',
  'classification':{'surface_code':'PROFILE:X','task_code':'EXECUTE:JSON'},'input':{'input_fields':{'x':1}},
  'card_resolution':{'status':'RESOLVED','mode':'EXACT','schema_invention_allowed':False},
  'authority_resolution':[{'authority_type':'PROFILE_SOURCE','authority_id':'PROFILE_X','source_refs':[ref('source_authority.txt')],'source_sha256':sha('source_authority.txt'),'run_id':'run-001','cross_run_declared':False,'currentness_evidence':binding('d_currentness_receipt.json')}],
  'adapter_binding':[],
  'runtime_schema':{'source_ref':ref('source_runtime_schema.json'),'sha256':sha('source_runtime_schema.json'),'schema_invention_allowed':False,'currentness_evidence':binding('d_currentness_receipt.json')},
  'provenance_reconstructible':True,'typed_context_sha256':'a'*64
 }

def e_base():
 return {
  'capability_id':'TYPED_RUNTIME_CONTEXT','capability_version':'v0.3-candidate','capability_class':'CONTEXT','owner':'S31-D',
  'lifecycle':{'artifact_maturity_label':'CANDIDATE_READ_ONLY','runtime_activation':False,'promotion_authority':'INDEPENDENT_LF_GOVERNANCE','self_certification_allowed':False,'canonical_vocabulary_status':'UNRESOLVED'},
  'authority_contract':'LF_AUTHORITY_CONTRACT','input_contract':'LF_TYPED_CONTEXT_INPUT','output_contract':'LF_TYPED_CONTEXT_OUTPUT',
  'dependencies':[{'capability_id':'CARD_RESOLUTION','version_constraint':'>=v0.1','critical':True}],
  'compatibility':{'consumer_contracts':['LF_RUNTIME_TYPED_CONTEXT_V1'],'boundary_adapters':['S26_TYPED_CONTEXT_V1_TO_SHARED_V0_2']},
  'execution_port':'TYPED_CONTEXT_RESOLUTION_PORT','adapter_bindings':['S26_RUNTIME_AUTHORITY_ADAPTER'],'evidence_contract':'LF_COMMON_EVIDENCE_ENVELOPE_V0_3',
  'currentness_binding':{'policy':'EXACT_SOURCE_REVISION','stale_action':'FAIL_CLOSED','evidence_ref':binding('e_currentness_receipt.json')['ref'],'evidence_sha256':binding('e_currentness_receipt.json')['sha256'],'resolver_id':TRUST},
  'source_refs':[ref('source_registry.py')],'source_digests':[sha('source_registry.py')],'claim_ceiling':'PROVENANCE'
 }

def f_base(level='STRUCTURAL',ceiling='STRUCTURAL'):
 inp={'x':1}; out={'ok':True}; executed=level!='STRUCTURAL'
 value={
  'receipt_version':'LF_EVIDENCE_V0_3','run_id':'run-001','producer_id':'S31_F_PRODUCER','capability_or_gate_id':'S31-F',
  'input':{'exact':inp,'digest':canonical(inp),'source_refs':[ref('provenance_source.txt')],'source_digests':[sha('provenance_source.txt')]},
  'validation_or_transformation':'DETERMINISTIC_VALIDATE','output':{'exact':out,'digest':canonical(out),'ref':'receipt://out'},
  'execution_identity':{'executed':executed,'execution_ref_kind':'BRANCH_HEAD' if executed else 'NOT_EXECUTED','executed_sha':HEAD if executed else None,'execution_id':'exec-001' if executed else None},
  'environment':'SANDBOX',
  'authority':{'source':'LF_AUTHORITY','source_ref':ref('source_authority.txt'),'source_digest':sha('source_authority.txt'),'source_revision':HEAD,'currentness':'CURRENT' if executed else 'UNKNOWN'},
  'provenance':{'reconstructible':executed,'refs':[ref('provenance_source.txt')],'digests':[sha('provenance_source.txt')]},
  'owner_receipt':{**binding('f_owner_receipt.json'),'owner_capability_id':'S31-F','preserved_without_rewrite':True},
  'extensions':{'s31.f.test':{'preserves_owner_semantics':True}},'evidence_level':level,'claim_ceiling':ceiling,'first_bad_hop':None,'repair_disposition':'NONE'
 }
 if executed:
  value['resolved_evidence']={'execution_receipt':binding('f_execution_receipt.json'),'authority_currentness_receipt':binding('f_authority_receipt.json'),'provenance_receipt':binding('f_provenance_receipt.json')}
 return value

def g_request():
 return {'port_version':'LF_RUNTIME_EXECUTION_PORT_V0_1_CANDIDATE','request_id':'run-001','typed_context_ref':ref('typed_context.json'),'typed_context_sha256':sha('typed_context.json'),'typed_context_resolver_id':TRUST,'governed_input':{'prompt':'bounded'},'output_contract_ref':'lf_runtime_execution_output_v0_1_candidate.schema.json','execution_budget':{'max_runtime_ms':1000,'max_output_units':2000},'runtime_policy':{'provider_or_adapter':'PROFILE_RUNTIME_EXECUTOR_ADAPTER','silent_fallback_allowed':False},'authority_decisions_forbidden':['AUTHORITY','CURRENTNESS','CARD_APPLICABILITY','PROMOTION','GOLDEN','PRODUCTION']}
def g_output():
 return {'raw_output':{'business_payload':'ok'},'runtime_receipt':{'run_id':'run-001','executor_id':'PROFILE_RUNTIME_EXECUTOR_ADAPTER','status':'PASS','receipt_ref':'receipt://runtime/001','receipt_sha256':'a'*64,'authority_grants_allowed':False,'downstream_authorized':False,'golden_authorized':False,'production_authorized':False,'authority_effects':[]},'transport_diagnostics':{},'resource_usage':{},'failure_code':None}

# D positives and IR-002 trusted-source adversarials.
d=d_base(); assert not schema_errors(D_SCHEMA,d); assert m.validate_shared_typed_context(d,RESOLVER)['status']==m.PASS; POS+=1
assert m.validate_shared_typed_context(d,None)['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE'; NEG+=1
assert m.validate_shared_typed_context(d,lambda r: {})['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE'; NEG+=1
x=d_base(); x['authority_resolution'][0]['source_sha256']='f'*64; assert m.validate_shared_typed_context(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=d_base(); x['authority_resolution'][0]['currentness_evidence']['resolver_id']='S31_D_PRODUCER'; assert schema_errors(D_SCHEMA,x); NEG+=1
x=d_base(); x['authority_resolution'][0]['run_id']='old-run'; assert m.validate_shared_typed_context(x,RESOLVER)['code']=='BLOCK_D_UNDECLARED_CROSS_RUN_AUTHORITY'; NEG+=1
x=d_base(); x['runtime_schema']['sha256']='short'; assert schema_errors(D_SCHEMA,x); NEG+=1
x=d_base(); x['authority_resolution'][0]['source_refs'].append(ref('provenance_source.txt')); assert schema_errors(D_SCHEMA,x); NEG+=1

# E source bytes/currentness are provider-derived.
e=e_base(); assert not schema_errors(E_SCHEMA,e); assert m.validate_registry_inventory_schema(E_INVENTORY,E_SCHEMA)['status']==m.PASS; assert m.validate_capability_manifest(e,RESOLVER)['status']==m.PASS; POS+=2
old=copy.deepcopy(E_INVENTORY); old['required_capability_manifest_fields']=['lifecycle_state' if z=='lifecycle' else z for z in old['required_capability_manifest_fields']]; assert m.validate_registry_inventory_schema(old,E_SCHEMA)['code']=='BLOCK_E_SOURCE_MODEL_REQUIRED_FIELDS_MISMATCH'; NEG+=1
x=e_base(); x['source_digests']=['12345678']; assert schema_errors(E_SCHEMA,x); NEG+=1
x=e_base(); assert m.validate_capability_manifest(x,None)['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE'; NEG+=1
x=e_base(); x['source_digests']=['f'*64]; assert m.validate_capability_manifest(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=e_base(); x['currentness_binding']['resolver_id']='S31-D'; assert schema_errors(E_SCHEMA,x); NEG+=1
x=e_base(); x['dependencies'].append(copy.deepcopy(x['dependencies'][0])); assert m.validate_capability_manifest(x,RESOLVER)['code']=='BLOCK_E_DUPLICATE_DEPENDENCY'; NEG+=1

# F owner receipt is resolved even STRUCTURAL; non-structural receipts are fully cross-bound.
f=f_base(); assert not schema_errors(F_SCHEMA,f); assert m.validate_evidence_envelope(f,RESOLVER)['status']==m.PASS; POS+=1
assert m.validate_evidence_envelope(f,None)['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE'; NEG+=1
x=f_base(); x['input']['digest']='1'*64; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_F_INPUT_DIGEST_MISMATCH'; NEG+=1
x=f_base(); x.pop('owner_receipt'); assert schema_errors(F_SCHEMA,x); NEG+=1
semantic=f_base('SEMANTIC','SEMANTIC'); assert not schema_errors(F_SCHEMA,semantic); assert m.validate_evidence_envelope(semantic,RESOLVER)['status']==m.PASS; POS+=1
x=f_base('SEMANTIC','SEMANTIC'); x['resolved_evidence']['execution_receipt']['sha256']='f'*64; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['run_id']='other-run'; assert m.validate_evidence_envelope(x,RESOLVER)['code'] in {'BLOCK_F_OWNER_RECEIPT_MISMATCH','BLOCK_F_EXECUTION_RECEIPT_MISMATCH'}; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['capability_or_gate_id']='OTHER'; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_F_EXECUTION_RECEIPT_MISMATCH'; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['execution_identity']['execution_id']='other-exec'; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_F_EXECUTION_RECEIPT_MISMATCH'; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['authority']['source_digest']='f'*64; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['authority']['source_revision']='a'*40; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_F_AUTHORITY_SOURCE_REVISION_MISMATCH'; NEG+=1
x=f_base('SEMANTIC','SEMANTIC'); x['provenance']['digests']=['f'*64]; assert m.validate_evidence_envelope(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=f_base('STRUCTURAL','BEHAVIORAL'); assert schema_errors(F_SCHEMA,x); NEG+=1
x=f_base(); x['extensions']['s31.f.extra']={'owner_specific':'preserved'}; assert not schema_errors(F_SCHEMA,x); POS+=1

# G resolves exact current Typed Context before provider invocation.
g=g_request(); assert not schema_errors(G_REQUEST_SCHEMA,g); assert m.validate_runtime_port_request(g,RESOLVER)['status']==m.PASS; POS+=1
x=copy.deepcopy(g); x['typed_context_sha256']='f'*64; assert m.validate_runtime_port_request(x,RESOLVER)['code']=='BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH'; NEG+=1
x=copy.deepcopy(g); x['typed_context_ref']=f"github://{RESOLVER.repo}@{'a'*40}/{EVIDENCE}/typed_context.json"; assert m.validate_runtime_port_request(x,RESOLVER)['code']=='BLOCK_TRUSTED_REF_RESOLUTION_FAILED'; NEG+=1
x=copy.deepcopy(g); x['typed_context_resolver_id']='S31_G'; assert schema_errors(G_REQUEST_SCHEMA,x); NEG+=1
x=copy.deepcopy(g); x['governed_input']={'prompt':'changed'}; assert m.validate_runtime_port_request(x,RESOLVER)['code']=='BLOCK_G_TYPED_CONTEXT_GOVERNED_INPUT_MISMATCH'; NEG+=1
x=copy.deepcopy(g); x['request_id']='other-run'; assert m.validate_runtime_port_request(x,RESOLVER)['code']=='BLOCK_G_TYPED_CONTEXT_REQUEST_ID_MISMATCH'; NEG+=1
assert m.validate_runtime_port_request(g,lambda r:{})['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE'; NEG+=1
x=copy.deepcopy(g); x['runtime_policy']['silent_fallback_allowed']=True; assert schema_errors(G_REQUEST_SCHEMA,x); NEG+=1
x=copy.deepcopy(g); x['authority_decisions_forbidden'].pop(); assert schema_errors(G_REQUEST_SCHEMA,x); NEG+=1
out=g_output(); assert not schema_errors(G_OUTPUT_SCHEMA,out); assert m.validate_runtime_port_output(out)['status']==m.PASS; POS+=1
for mutate,code in [
 (lambda x:x['runtime_receipt'].__setitem__('production_authorized',True),'BLOCK_G_NESTED_AUTHORITY_FLAG'),
 (lambda x:x['runtime_receipt'].__setitem__('authority_effects',['ENABLE_PRODUCTION']),'BLOCK_G_NESTED_AUTHORITY_EFFECT'),
 (lambda x:x['runtime_receipt'].__setitem__('authority_grants_allowed',True),'BLOCK_G_NESTED_AUTHORITY_GRANT_ALLOWED'),
 (lambda x:x['runtime_receipt'].__setitem__('nested',{'golden_authorized':True}),'BLOCK_G_NESTED_AUTHORITY_FLAG')]:
 x=copy.deepcopy(out); mutate(x); assert m.validate_runtime_port_output(x)['code']==code; NEG+=1

assert POS>=8,POS
assert NEG>=32,NEG
print(json.dumps({'contract':'S31_DG_CONTRACT_MATRIX_V0_2','schemas_valid':['D_TYPED_CONTEXT_V0_2','E_CAPABILITY_MANIFEST_V0_3','F_EVIDENCE_ENVELOPE_V0_3','G_RUNTIME_REQUEST_V0_1','G_RUNTIME_OUTPUT_V0_1'],'positive_cases':POS,'negative_fail_closed_cases':NEG,'trusted_resolver':'QUALITY_PACK_TRUSTED_REF_RESOLVER_V1','result':'PASS'},sort_keys=True))
