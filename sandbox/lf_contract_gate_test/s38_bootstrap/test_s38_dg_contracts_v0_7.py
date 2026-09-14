#!/usr/bin/env python3
from __future__ import annotations
import copy,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
REPO_ROOT=Path(subprocess.check_output(['git','-C',str(ROOT),'rev-parse','--show-toplevel'],text=True).strip())
S31=ROOT.parent/'s31_bootstrap'; sys.path[:0]=[str(ROOT),str(S31)]
import validate_s38_dg_contracts_v0_7 as m
from s38_governed_resolution_v0_4 import S38GovernedRefResolver,ResolutionError,RUNTIME_TCB_PATHS,EVIDENCE_TCB_PATHS,canonical_manifest_bytes,resolve_source
EXPECTED_SIGNER='b464326ed6c6db0e93959588b952a74e5fc2fe30'
REPO='cristhianlujan/claude-persona-lf-patch'; HIST='191b53fca993bf28aefccf5e1e67007ad9a35dfa'; BASE='01f53ca5fb3d4d060e482fce64bddaeb1c383eae'; EVIDENCE='2c6435542dc4f3fa588afa9d80ca5e92740e62ef'; ALT='e75cab6e71c0f880f72726439e952de78ea4931f'
OLD='sandbox/lf_contract_gate_test/s31_bootstrap/trusted_evidence'; NEW='sandbox/lf_contract_gate_test/s38_bootstrap/trusted_evidence'
def git(*a,binary=False):
 o=subprocess.check_output(['git','-C',str(REPO_ROOT),*a]); return o if binary else o.decode().strip()
def pin(rev,path):
 raw=git('show',f'{rev}:{path}',binary=True); return {'revision':rev,'path':path,'blob_sha':git('rev-parse',f'{rev}:{path}'),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def manifest():
 head=git('rev-parse','HEAD'); inv=json.loads((ROOT/'s38_ir008_historical_pin_inventory_v0_1.json').read_text()); hist=[]
 for x in inv['pins']:
  rest=x['ref'].split('@',1)[1]; rev,path=rest.split('/',1); hist.append({'ref':x['ref'],**pin(rev,path)})
 return {'manifest_version':'LF_TRUSTED_SUBJECT_MANIFEST_V1','profile':'S38_DG_IR008','repository':REPO,'repository_id':1244397752,'candidate_sha':head,'runtime_tcb':[pin(head,p) for p in sorted(RUNTIME_TCB_PATHS)],'evidence_tcb':[pin(head,p) for p in sorted(EVIDENCE_TCB_PATHS)],'frozen_quality_pack':[],'historical_pins':hist,'authority':{'merge':'NONE','golden':'NONE','runtime':'NONE','scheduler':'NONE','production':'NONE','promotion':'NONE'}}
SUBJECT=manifest(); SUBJECT_SHA=hashlib.sha256(canonical_manifest_bytes(SUBJECT)).hexdigest(); RECEIPT={'status':'VERIFIED_EXTERNAL_SIGSTORE','subject_sha256':SUBJECT_SHA,'signer_digest':EXPECTED_SIGNER,'source_digest':SUBJECT['candidate_sha'],'repository':REPO,'repository_id':1244397752}; R=S38GovernedRefResolver(SUBJECT,RECEIPT,EXPECTED_SIGNER); TRUST=m.TRUSTED_RESOLVER_ID
POS=NEG=0
def ref(path,rev):return f'github://{REPO}@{rev}/{path}'
def obs(path,rev):return R.resolve(ref(path,rev))
def bind(path,rev,resolver_id=TRUST):
 o=obs(path,rev); return {'ref':ref(path,rev),'sha256':o['sha256'],'resolver_id':resolver_id}
def canonical(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
def f_base(level='PROVENANCE_EXECUTION',ceiling='PROVENANCE_EXECUTION'):
 inp={'x':1}; out={'ok':True}
 return {'receipt_version':'LF_EVIDENCE_V0_5','run_id':'run-001','producer_id':'S38_F_PRODUCER','capability_or_gate_id':'S38-F','input':{'exact':inp,'digest':canonical(inp),'source_refs':[ref(f'{OLD}/provenance_source.txt',HIST)],'source_digests':['e1dbd6467d351be354bc99a10265ebaa0eac926c200ef1b038c12f27a0126c1c']},'validation_or_transformation':'DETERMINISTIC_VALIDATE','output':{'exact':out,'digest':canonical(out),'ref':'receipt://out'},'execution_identity':{'executed':True,'execution_ref_kind':'IMMUTABLE_COMMIT','executed_sha':EVIDENCE,'execution_id':'exec-001'},'environment':'SANDBOX','authority':{'source':'LF_AUTHORITY','source_ref':ref(f'{OLD}/source_authority.txt',HIST),'source_digest':'73729407e4723f00a5848babb8039feacbe876561e7459473ae4715dbc0c46bc','source_revision':HIST,'currentness':'CURRENT'},'provenance':{'reconstructible':True,'refs':[ref(f'{OLD}/provenance_source.txt',HIST)],'digests':['e1dbd6467d351be354bc99a10265ebaa0eac926c200ef1b038c12f27a0126c1c']},'owner_receipt':{**bind(f'{NEW}/f_owner_receipt_v0_5.json',EVIDENCE),'owner_capability_id':'S38-F','preserved_without_rewrite':True},'extensions':{'s38.f.v05':{'cross_binding':m.CROSS_BINDING_VERSION}},'resolved_evidence':{'execution_receipt':bind(f'{NEW}/f_execution_receipt_v0_5.json',EVIDENCE),'authority_currentness_receipt':bind(f'{NEW}/f_authority_receipt_v0_5.json',EVIDENCE),'provenance_receipt':bind(f'{NEW}/f_provenance_receipt_v0_5.json',EVIDENCE)},'evidence_level':level,'claim_ceiling':ceiling,'first_bad_hop':None,'repair_disposition':'NONE'}
def g_request(name='typed_context.json'):
 path=f'{OLD}/{name}'; o=obs(path,BASE); return {'port_version':'LF_RUNTIME_EXECUTION_PORT_V0_2_CANDIDATE','request_id':'run-001','typed_context_ref':ref(path,BASE),'typed_context_sha256':o['sha256'],'typed_context_resolver_id':TRUST,'governed_input':{'prompt':'bounded'},'output_contract_ref':'lf_runtime_execution_output_v0_2_candidate.schema.json','execution_budget':{'max_runtime_ms':1000,'max_output_units':2000},'runtime_policy':{'provider_or_adapter':'PROFILE_RUNTIME_EXECUTOR_ADAPTER','silent_fallback_allowed':False},'authority_decisions_forbidden':['AUTHORITY','CURRENTNESS','CARD_APPLICABILITY','PROMOTION','GOLDEN','PRODUCTION']}
def e_base():
 c=bind(f'{OLD}/e_currentness_receipt.json',HIST); src=obs(f'{OLD}/source_registry.py',HIST)
 return {'capability_id':'TYPED_RUNTIME_CONTEXT','capability_version':'v0.3-candidate','capability_class':'CONTEXT','owner':'S31-D','lifecycle':{'artifact_maturity_label':'CANDIDATE_READ_ONLY','runtime_activation':False,'promotion_authority':'INDEPENDENT_LF_GOVERNANCE','self_certification_allowed':False,'canonical_vocabulary_status':'UNRESOLVED'},'authority_contract':'LF_AUTHORITY_CONTRACT','input_contract':'LF_TYPED_CONTEXT_INPUT','output_contract':'LF_TYPED_CONTEXT_OUTPUT','dependencies':[{'capability_id':'CARD_RESOLUTION','version_constraint':'>=v0.1','critical':True}],'compatibility':{'consumer_contracts':['LF_RUNTIME_TYPED_CONTEXT_V1'],'boundary_adapters':['S26_TYPED_CONTEXT_V1_TO_SHARED_V0_2']},'execution_port':'TYPED_CONTEXT_RESOLUTION_PORT','adapter_bindings':['S26_RUNTIME_AUTHORITY_ADAPTER'],'evidence_contract':'LF_COMMON_EVIDENCE_ENVELOPE_V0_7','currentness_binding':{'policy':'EXACT_SOURCE_REVISION','stale_action':'FAIL_CLOSED','evidence_ref':c['ref'],'evidence_sha256':c['sha256'],'resolver_id':'QUALITY_PACK_TRUSTED_REF_RESOLVER_V1'},'source_refs':[ref(f'{OLD}/source_registry.py',HIST)],'source_digests':[src['sha256']],'claim_ceiling':'PROVENANCE'}
def g_output():return {'raw_output':{'business_payload':'ok'},'runtime_receipt':{'run_id':'run-001','executor_id':'PROFILE_RUNTIME_EXECUTOR_ADAPTER','status':'PASS','receipt_ref':'receipt://runtime/001','receipt_sha256':'a'*64,'authority_grants_allowed':False,'downstream_authorized':False,'golden_authorized':False,'production_authorized':False,'authority_effects':[]},'transport_diagnostics':{},'resource_usage':{},'failure_code':None}
# trust positives
assert R.verified and R.artifact_head==SUBJECT['candidate_sha']; POS+=1
for field,bad,code in [('signer_digest','0'*40,'BLOCK_EXTERNAL_ATTESTATION_BINDING_MISMATCH'),('source_digest','0'*40,'BLOCK_EXTERNAL_ATTESTATION_BINDING_MISMATCH'),('subject_sha256','0'*64,'BLOCK_EXTERNAL_ATTESTATION_BINDING_MISMATCH')]:
 x=dict(RECEIPT);x[field]=bad
 try:S38GovernedRefResolver(SUBJECT,x,EXPECTED_SIGNER);raise AssertionError(field)
 except ResolutionError as e:assert e.code==code,(field,e.code)
 NEG+=1
# explicit historical identity only
status,_=resolve_source(R,ref(f'{OLD}/source_authority.txt',ALT),'73729407e4723f00a5848babb8039feacbe876561e7459473ae4715dbc0c46bc','alt',require_current_content=False);assert status.get('resolver_code')=='BLOCK_HISTORICAL_REF_NOT_ATTESTED',status;NEG+=1
# E strict schema + semantic
x=e_base();r=m.validate_capability_manifest(x,R);assert r['status']==m.PASS,r;POS+=1
x['undeclared_surface']=1;r=m.validate_capability_manifest(x,R);assert r['code']=='BLOCK_E_MANIFEST_SCHEMA_INVALID',r;NEG+=1
# F positive and tier fail closed
x=f_base();r=m.validate_evidence_envelope(x,R);assert r['status']==m.PASS,r;POS+=1
for tier in ('SEMANTIC','BEHAVIORAL'):
 x=f_base(tier,tier);r=m.validate_evidence_envelope(x,R);assert r['code']=='BLOCK_F_CLAIM_TIER_NOT_EARNED',r;NEG+=1
x=f_base();x['undeclared_surface']=1;r=m.validate_evidence_envelope(x,R);assert r['code']=='BLOCK_F_ENVELOPE_SCHEMA_INVALID',r;NEG+=1
# G request/output schema + nested governance
x=g_request();r=m.validate_runtime_port_request(x,R);assert r['status']==m.PASS,r;POS+=1
x=g_request();x['undeclared_surface']=1;r=m.validate_runtime_port_request(x,R);assert r['code']=='BLOCK_G_REQUEST_SCHEMA_INVALID',r;NEG+=1
x=g_request('typed_context_invalid_authority.json');r=m.validate_runtime_port_request(x,R);assert r['code']=='BLOCK_G_TYPED_CONTEXT_SEMANTIC_GOVERNANCE',r;NEG+=1
o=g_output();r=m.validate_runtime_port_output(o,R);assert r['status']==m.PASS,r;POS+=1
x=copy.deepcopy(o);x['undeclared_surface']=1;r=m.validate_runtime_port_output(x,R);assert r['code']=='BLOCK_G_OUTPUT_SCHEMA_INVALID',r;NEG+=1
x=copy.deepcopy(o);x['runtime_receipt']['authority_effects']=['PROMOTE_GOLDEN'];r=m.validate_runtime_port_output(x,R);assert r['code'] in {'BLOCK_G_OUTPUT_SCHEMA_INVALID','BLOCK_G_NESTED_AUTHORITY_EFFECT'},r;NEG+=1
# whole-checkout/local TCB tamper cannot reuse genuine subject+receipt
for rel in sorted(RUNTIME_TCB_PATHS|EVIDENCE_TCB_PATHS):
 p=REPO_ROOT/rel; raw=p.read_bytes()
 try:
  p.write_bytes(raw+b'\n# attacker mutation\n')
  try:S38GovernedRefResolver(SUBJECT,RECEIPT,EXPECTED_SIGNER);raise AssertionError(rel)
  except ResolutionError as e:assert e.code=='BLOCK_ATTESTED_TCB_BYTE_MISMATCH',(rel,e.code)
  NEG+=1
 finally:p.write_bytes(raw)
# repeated offline constructor no network API requirement
for _ in range(25):assert S38GovernedRefResolver(SUBJECT,RECEIPT,EXPECTED_SIGNER).verified
POS+=1
print(json.dumps({'contract':'S38_DG_IR007_RESTRICTION_REPAIR_V0_7','positive_cases':POS,'negative_fail_closed_cases':NEG,'resolver_id':TRUST,'expected_signer_digest':EXPECTED_SIGNER,'subject_sha256':SUBJECT_SHA,'result':'PASS'},sort_keys=True))
