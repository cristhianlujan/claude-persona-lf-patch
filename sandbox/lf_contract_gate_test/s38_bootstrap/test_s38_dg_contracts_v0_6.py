#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parent
S31=ROOT.parent/'s31_bootstrap'
sys.path.insert(0,str(ROOT)); sys.path.insert(0,str(S31))
import validate_s38_dg_contracts_v0_6 as m
from s38_governed_resolution_v0_3 import resolve_source, _safe_git_env, ResolutionError
import s31_trusted_resolution_v0_1 as legacy_trust

R=m.S38GovernedRefResolver()
TRUST=m.TRUSTED_RESOLVER_ID
REPO=R.repo
HIST='191b53fca993bf28aefccf5e1e67007ad9a35dfa'
BASE='01f53ca5fb3d4d060e482fce64bddaeb1c383eae'
EVIDENCE_REV=subprocess.check_output(['git','-C',str(R.root),'log','-1','--format=%H','--','sandbox/lf_contract_gate_test/s38_bootstrap/trusted_evidence/f_execution_receipt_v0_5.json'],text=True).strip()
OLD_E='sandbox/lf_contract_gate_test/s31_bootstrap/trusted_evidence'
NEW_E='sandbox/lf_contract_gate_test/s38_bootstrap/trusted_evidence'
EXPECTED='1f5f85cdc08a6c80764af02204b39aadec993104a6949736809aa33aeb6d6810'
POS=NEG=0

def ref(path,rev): return f'github://{REPO}@{rev}/{path}'
def obs(path,rev): return R.resolve(ref(path,rev))
def bind(path,rev,resolver_id=TRUST):
    o=obs(path,rev); return {'ref':ref(path,rev),'sha256':o['sha256'],'resolver_id':resolver_id}
def canonical(v): return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

def f_base(level='PROVENANCE_EXECUTION',ceiling='PROVENANCE_EXECUTION'):
    inp={'x':1}; out={'ok':True}
    return {
      'receipt_version':'LF_EVIDENCE_V0_5','run_id':'run-001','producer_id':'S38_F_PRODUCER','capability_or_gate_id':'S38-F',
      'input':{'exact':inp,'digest':canonical(inp),'source_refs':[ref(f'{OLD_E}/provenance_source.txt',HIST)],'source_digests':['e1dbd6467d351be354bc99a10265ebaa0eac926c200ef1b038c12f27a0126c1c']},
      'validation_or_transformation':'DETERMINISTIC_VALIDATE','output':{'exact':out,'digest':canonical(out),'ref':'receipt://out'},
      'execution_identity':{'executed':True,'execution_ref_kind':'IMMUTABLE_COMMIT','executed_sha':EVIDENCE_REV,'execution_id':'exec-001'},
      'environment':'SANDBOX',
      'authority':{'source':'LF_AUTHORITY','source_ref':ref(f'{OLD_E}/source_authority.txt',HIST),'source_digest':'73729407e4723f00a5848babb8039feacbe876561e7459473ae4715dbc0c46bc','source_revision':HIST,'currentness':'CURRENT'},
      'provenance':{'reconstructible':True,'refs':[ref(f'{OLD_E}/provenance_source.txt',HIST)],'digests':['e1dbd6467d351be354bc99a10265ebaa0eac926c200ef1b038c12f27a0126c1c']},
      'owner_receipt':{**bind(f'{NEW_E}/f_owner_receipt_v0_5.json',EVIDENCE_REV),'owner_capability_id':'S38-F','preserved_without_rewrite':True},
      'extensions':{'s38.f.v05':{'cross_binding':m.CROSS_BINDING_VERSION}},
      'resolved_evidence':{
        'execution_receipt':bind(f'{NEW_E}/f_execution_receipt_v0_5.json',EVIDENCE_REV),
        'authority_currentness_receipt':bind(f'{NEW_E}/f_authority_receipt_v0_5.json',EVIDENCE_REV),
        'provenance_receipt':bind(f'{NEW_E}/f_provenance_receipt_v0_5.json',EVIDENCE_REV)},
      'evidence_level':level,'claim_ceiling':ceiling,'first_bad_hop':None,'repair_disposition':'NONE'}

def g_request(name):
    path=f'{OLD_E}/{name}'; o=obs(path,BASE)
    return {'port_version':'LF_RUNTIME_EXECUTION_PORT_V0_1_CANDIDATE','request_id':'run-001','typed_context_ref':ref(path,BASE),'typed_context_sha256':o['sha256'],'typed_context_resolver_id':TRUST,'governed_input':{'prompt':'bounded'},'output_contract_ref':'lf_runtime_execution_output_v0_1_candidate.schema.json','execution_budget':{'max_runtime_ms':1000,'max_output_units':2000},'runtime_policy':{'provider_or_adapter':'PROFILE_RUNTIME_EXECUTOR_ADAPTER','silent_fallback_allowed':False},'authority_decisions_forbidden':['AUTHORITY','CURRENTNESS','CARD_APPLICABILITY','PROMOTION','GOLDEN','PRODUCTION']}

# Resolver is internally anchored and the canonical module/policy match remote bytes.
assert R.verified and R.artifact_head
POS+=1

# Caller-controlled old resolver, including one rooted at a tampered clone, is not accepted.
with tempfile.TemporaryDirectory() as attack_td:
    attack_root=Path(attack_td)/'repo'
    subprocess.run(['git','clone','-q','--branch','lf/s38-ir007-repair-gpt-exclusive-20260913','https://github.com/cristhianlujan/claude-persona-lf-patch.git',str(attack_root)],check=True)
    forged=attack_root/f'{OLD_E}/source_authority.txt'
    forged.write_text('ATTACKER-FORGED-AUTHORITY\n',encoding='utf-8')
    legacy=legacy_trust.TrustedRefResolver(attack_root)
    x=f_base(); res=m.validate_evidence_envelope(x,legacy)
    assert res['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE',res
    NEG+=1

# A copied S38 resolver module with local byte tampering cannot self-certify merely because HEAD is canonical.
with tempfile.TemporaryDirectory() as attack_td:
    attack_root=Path(attack_td)/'repo'
    subprocess.run(['git','clone','-q','--branch','lf/s38-ir007-repair-gpt-exclusive-20260913','https://github.com/cristhianlujan/claude-persona-lf-patch.git',str(attack_root)],check=True)
    mod_path=attack_root/'sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_resolution_v0_3.py'
    mod_path.write_text(mod_path.read_text(encoding='utf-8')+'\n# attacker local mutation\n',encoding='utf-8')
    spec=importlib.util.spec_from_file_location('s38_tampered_resolver',mod_path)
    tampered=importlib.util.module_from_spec(spec); sys.modules[spec.name]=tampered; spec.loader.exec_module(tampered)
    try:
        tampered.S38GovernedRefResolver()
        raise AssertionError('tampered resolver unexpectedly constructed')
    except tampered.ResolutionError as exc:
        assert exc.code=='BLOCK_GOVERNED_ARTIFACT_BYTE_MISMATCH',exc.code
    NEG+=1

# Archived historical path deleted at current artifact head remains current only via exact registry attestation.
arch='github://cristhianlujan/claude-persona-lf-patch@be6c0f8a320c5cdcfa242ee775ba769745eb82df/profiles/ui_architect/schemas/runtime_output.schema.json'
status,o=resolve_source(R,arch,'bed06e7a37a82a6e1baa9b1da4edb7969456ce64c4270fdd8e5db0f14845d425','archive',require_current_content=True)
assert status['status']==m.PASS,status
POS+=1
# Same bytes/ref shape from a different historical revision is not automatically current.
parent=subprocess.check_output(['git','-C',str(R.root),'rev-parse','be6c0f8a320c5cdcfa242ee775ba769745eb82df^'],text=True).strip()
alt=f'github://{REPO}@{parent}/profiles/ui_architect/schemas/runtime_output.schema.json'
try: alt_o=R.resolve(alt)
except Exception: alt_o=None
if alt_o and alt_o['sha256']=='bed06e7a37a82a6e1baa9b1da4edb7969456ce64c4270fdd8e5db0f14845d425':
    status,_=resolve_source(R,alt,alt_o['sha256'],'archive-alt',require_current_content=True)
    assert status['code']=='BLOCK_PROVIDER_SOURCE_STALE',status
    NEG+=1

# Earned deterministic/provenance tier passes with resolver-bound receipts.
f=f_base(); res=m.validate_evidence_envelope(f,R)
assert res['status']==m.PASS,res
assert res['earned_tier']=='PROVENANCE_EXECUTION' and res['cross_binding_sha256']==EXPECTED,res
POS+=1

# Producer-authored higher tier is blocked before self-consistent receipt authorship can elevate it.
for tier in ('SEMANTIC','BEHAVIORAL'):
    x=f_base(tier,tier)
    res=m.validate_evidence_envelope(x,R)
    assert res['code']=='BLOCK_F_CLAIM_TIER_NOT_EARNED',(tier,res)
    NEG+=1

# Fake witness is not enough; witness must be policy allowlisted and independently resolvable.
x=f_base('SEMANTIC','SEMANTIC'); x['extensions']['s38.claim_witness']={'ref':ref(f'{NEW_E}/f_owner_receipt_v0_5.json',EVIDENCE_REV),'sha256':obs(f'{NEW_E}/f_owner_receipt_v0_5.json',EVIDENCE_REV)['sha256'],'resolver_id':TRUST}
res=m.validate_evidence_envelope(x,R); assert res['code']=='BLOCK_F_CLAIM_TIER_NOT_EARNED',res
NEG+=1

# Declared v0.5 schema is actually enforced; old validator accepted unknown surface.
x=f_base(); x['undeclared_surface']='should-block'
res=m.validate_evidence_envelope(x,R); assert res['code']=='BLOCK_F_ENVELOPE_SCHEMA_INVALID',res
NEG+=1

# Claim-bound receipt substitution remains closed.
x=f_base(); x['resolved_evidence']['execution_receipt']=bind(f'{OLD_E}/f_execution_receipt_v0_4.json',BASE,legacy_trust.TRUSTED_RESOLVER_ID)
res=m.validate_evidence_envelope(x,R); assert res['code'] in {'BLOCK_F_EXECUTION_RECEIPT_REVISION_MISMATCH','BLOCK_F_CROSS_BINDING_VERSION_MISMATCH','BLOCK_F_EXECUTION_RECEIPT_MISMATCH'},res
NEG+=1

# G exact Typed Context + nested governance passes with the S38 resolver.
g=g_request('typed_context.json'); res=m.validate_runtime_port_request(g,R); assert res['status']==m.PASS,res
POS+=1
# Correct outer digest cannot hide invalid nested authority.
x=g_request('typed_context_invalid_authority.json'); res=m.validate_runtime_port_request(x,R); assert res['code']=='BLOCK_G_TYPED_CONTEXT_SEMANTIC_GOVERNANCE',res
NEG+=1
# Caller-provided old resolver rejected at G boundary too.
res=m.validate_runtime_port_request(g,legacy); assert res['code']=='BLOCK_UNTRUSTED_RESOLVER_TYPE',res
NEG+=1


assert 'canonical_repository' not in R.policy_snapshot and R.repo=='cristhianlujan/claude-persona-lf-patch'; POS+=1
safe=_safe_git_env()
for key in ('https_proxy','HTTPS_PROXY','ALL_PROXY','GIT_PROXY_COMMAND','GIT_SSL_NO_VERIFY','GIT_SSL_CAINFO','SSL_CERT_FILE'): assert key not in safe,(key,safe)
POS+=1
policy_path=ROOT/'s38_governed_trust_policy_v0_2.json'; original_policy=policy_path.read_bytes()
try:
 p=json.loads(original_policy); p['claim_tier']['max_without_independent_witness']='BEHAVIORAL'; p['canonical_repository']={'remote_url':'https://attacker.invalid/evil.git'}; policy_path.write_text(json.dumps(p),encoding='utf-8')
 x=f_base('SEMANTIC','SEMANTIC'); res=m.validate_evidence_envelope(x,R); assert res['code']=='BLOCK_F_CLAIM_TIER_NOT_EARNED',res; NEG+=1
finally: policy_path.write_bytes(original_policy)
f_schema=ROOT/'lf_common_evidence_envelope_v0_6_candidate.schema.json'; original_schema=f_schema.read_bytes()
try:
 s=json.loads(original_schema); s['additionalProperties']=True; f_schema.write_text(json.dumps(s),encoding='utf-8')
 x=f_base(); x['undeclared_surface']='must-still-block'; res=m.validate_evidence_envelope(x,R); assert res['code']=='BLOCK_F_ENVELOPE_SCHEMA_INVALID',res; NEG+=1
finally: f_schema.write_bytes(original_schema)
try:
 R.resolve('github://%s@%s/%s/source_authority.txt'%(REPO,'0'*40,OLD_E)); raise AssertionError('unpublished revision unexpectedly resolved')
except ResolutionError: NEG+=1
x=f_base(); x['capability_or_gate_id']='S38-F-OTHER'; res=m.validate_evidence_envelope(x,R); assert res['code']=='BLOCK_F_OWNER_CAPABILITY_BINDING_MISMATCH',res; NEG+=1
x=g_request('typed_context.json'); x['governed_input']={'prompt':'tampered'}; res=m.validate_runtime_port_request(x,R); assert res['code']=='BLOCK_G_TYPED_CONTEXT_GOVERNED_INPUT_MISMATCH',res; NEG+=1
x=g_request('typed_context.json'); x['authority_decisions_forbidden'].remove('GOLDEN'); res=m.validate_runtime_port_request(x,R); assert res['code']=='BLOCK_G_AUTHORITY_FORBIDDEN_SET_INCOMPLETE',res; NEG+=1

# Canonical-policy tamper before resolver construction fails against the fixed canonical remote.
with tempfile.TemporaryDirectory() as attack_td:
    attack_root=Path(attack_td)/'repo'
    subprocess.run(['git','clone','-q','--branch','lf/s38-ir007-repair-gpt-exclusive-20260913','https://github.com/cristhianlujan/claude-persona-lf-patch.git',str(attack_root)],check=True)
    pol=attack_root/'sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_trust_policy_v0_2.json'
    obj=json.loads(pol.read_text()); obj['claim_tier']['max_without_independent_witness']='BEHAVIORAL'; obj['canonical_repository']={'remote_url':'https://attacker.invalid/evil.git'}; pol.write_text(json.dumps(obj))
    mod_path=attack_root/'sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_resolution_v0_3.py'
    spec=importlib.util.spec_from_file_location('s38_policy_tamper_resolver',mod_path); tampered=importlib.util.module_from_spec(spec); sys.modules[spec.name]=tampered; spec.loader.exec_module(tampered)
    try:
        tampered.S38GovernedRefResolver(); raise AssertionError('policy-tampered resolver unexpectedly constructed')
    except tampered.ResolutionError as exc:
        assert exc.code=='BLOCK_GOVERNED_ARTIFACT_BYTE_MISMATCH',exc.code
    NEG+=1

# Enforced schema tamper before construction is load-bearing and fails closed.
with tempfile.TemporaryDirectory() as attack_td:
    attack_root=Path(attack_td)/'repo'
    subprocess.run(['git','clone','-q','--branch','lf/s38-ir007-repair-gpt-exclusive-20260913','https://github.com/cristhianlujan/claude-persona-lf-patch.git',str(attack_root)],check=True)
    sch=attack_root/'sandbox/lf_contract_gate_test/s38_bootstrap/lf_common_evidence_envelope_v0_6_candidate.schema.json'
    obj=json.loads(sch.read_text()); obj['additionalProperties']=True; sch.write_text(json.dumps(obj))
    mod_path=attack_root/'sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_resolution_v0_3.py'
    spec=importlib.util.spec_from_file_location('s38_schema_tamper_resolver',mod_path); tampered=importlib.util.module_from_spec(spec); sys.modules[spec.name]=tampered; spec.loader.exec_module(tampered)
    try:
        tampered.S38GovernedRefResolver(); raise AssertionError('schema-tampered resolver unexpectedly constructed')
    except tampered.ResolutionError as exc:
        assert exc.code=='BLOCK_GOVERNED_ARTIFACT_BYTE_MISMATCH',exc.code
    NEG+=1

# Unregistered archival identity remains fail-closed.
parent=subprocess.check_output(['git','-C',str(R.root),'rev-parse','be6c0f8a320c5cdcfa242ee775ba769745eb82df^'],text=True).strip()
alt_ref=f'github://{REPO}@{parent}/profiles/ui_architect/schemas/runtime_output.schema.json'
try:
    alt_obs=R.resolve(alt_ref)
    status,_=resolve_source(R,alt_ref,alt_obs['sha256'],'archive-unregistered',require_current_content=True)
    assert status['code']=='BLOCK_PROVIDER_SOURCE_STALE',status
    NEG+=1
except ResolutionError:
    NEG+=1

# Authority/provenance replay without the v0.5 common binding fails closed.
for key,name in (('authority_currentness_receipt','f_authority_receipt_v0_4.json'),('provenance_receipt','f_provenance_receipt_v0_4.json')):
    x=f_base(); x['resolved_evidence'][key]=bind(f'{OLD_E}/{name}',BASE)
    res=m.validate_evidence_envelope(x,R)
    assert res['status']!=m.PASS,(key,res)
    NEG+=1

# Same-content historical identity substitutions remain bound to exact identity.
ALT_HIST='e75cab6e71c0f880f72726439e952de78ea4931f'
for attack in ('input','authority','provenance'):
    x=f_base()
    if attack=='input': x['input']['source_refs']=[ref(f'{OLD_E}/provenance_source.txt',ALT_HIST)]
    elif attack=='authority': x['authority']['source_ref']=ref(f'{OLD_E}/source_authority.txt',ALT_HIST); x['authority']['source_revision']=ALT_HIST
    else: x['provenance']['refs']=[ref(f'{OLD_E}/provenance_source.txt',ALT_HIST)]
    res=m.validate_evidence_envelope(x,R)
    assert res['status']!=m.PASS,(attack,res)
    NEG+=1

# Hostile caller transport environment does not redirect canonical attestation/fetch.
hostile={'https_proxy':'http://127.0.0.1:9','HTTPS_PROXY':'http://127.0.0.1:9','ALL_PROXY':'socks5://127.0.0.1:9','GIT_PROXY_COMMAND':'false','GIT_SSL_NO_VERIFY':'1','GIT_SSL_CAINFO':'/tmp/attacker-ca.pem','SSL_CERT_FILE':'/tmp/attacker-ca.pem','GIT_CONFIG_COUNT':'1','GIT_CONFIG_KEY_0':'url.file:///tmp/evil.insteadOf','GIT_CONFIG_VALUE_0':'https://github.com/'}
old_env={k:os.environ.get(k) for k in hostile}
try:
    os.environ.update(hostile)
    r2=m.S38GovernedRefResolver()
    assert r2.verified and r2.repo==REPO,(r2.verified,r2.repo)
    sample=r2.resolve(ref(f'{OLD_E}/source_authority.txt',HIST))
    assert sample['sha256']=='73729407e4723f00a5848babb8039feacbe876561e7459473ae4715dbc0c46bc',sample['sha256']
    r2.close(); POS+=1
finally:
    for k,v in old_env.items():
        if v is None: os.environ.pop(k,None)
        else: os.environ[k]=v
print(json.dumps({'contract':'S38_DG_IR006_RESTRICTION_REPAIR_V0_6','positive_cases':POS,'negative_fail_closed_cases':NEG,'evidence_revision':EVIDENCE_REV,'cross_binding_sha256':EXPECTED,'resolver_id':TRUST,'result':'PASS'},sort_keys=True))
R.close()
