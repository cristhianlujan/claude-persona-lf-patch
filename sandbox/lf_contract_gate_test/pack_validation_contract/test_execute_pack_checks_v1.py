#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, os, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MODULE=ROOT/'sandbox/lf_contract_gate_test/pack_validation_contract/execute_pack_checks_v1.py'
spec=importlib.util.spec_from_file_location('execute_pack_checks_v1',MODULE); mod=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(mod)
BASE='a'*40; HEAD='b'*40
VALIDATION=json.loads((ROOT/'gobernanza/contratos/pack_validation_define_contract_v1.json').read_text(encoding='utf-8'))
DISCOVERY=json.loads((ROOT/'gobernanza/contratos/pack_discovery_resolve_affected_packs_v1.json').read_text(encoding='utf-8'))
EXECUTION=json.loads((ROOT/'gobernanza/contratos/pack_validation_execute_pack_checks_v1.json').read_text(encoding='utf-8'))
assert EXECUTION['durable_name']=='PACK_VALIDATION_EXECUTE_PACK_CHECKS'
assert EXECUTION['handoff']=='PROFILE_PACK_VALIDATION_CLEAN_VALIDATOR'
checks=0

def make_validator(root:Path, rel:str, body:str):
    p=root/rel/'validators'; p.mkdir(parents=True,exist_ok=True); f=p/'validate_pack.py'; f.write_text(body,encoding='utf-8'); return f

def result(root:Path,packs,status='PASS',**kw):
    dr={'status':status,'base_sha':BASE,'head_sha':HEAD,'affected_packs':packs,'validators_executed':False}
    return mod.execute_pack_checks(repo_root=root,validation_contract=VALIDATION,discovery_contract=DISCOVERY,discovery_result=dr,base_sha=kw.pop('base_sha',BASE),head_sha=kw.pop('head_sha',HEAD),verify_git=False,**kw)

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    make_validator(root,'profiles/alpha',"import json; print(json.dumps({'status':'PASS'}))")
    r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/alpha','exists_at_head':True}])
    assert r['status']=='PASS' and r['evidence']['pass_count']==1 and r['affected_packs'][0]['validator_ref']=='profiles/alpha/validators/validate_pack.py'; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); make_validator(root,'profiles/beta',"print('ok')"); make_validator(root,'skills/payments',"print('ok')")
    r=result(root,[{'pack_type':'SKILL_PACK','pack_root':'skills/payments','exists_at_head':True},{'pack_type':'PROFILE_PACK','pack_root':'profiles/beta','exists_at_head':True}])
    assert r['status']=='PASS' and [x['pack_type'] for x in r['affected_packs']]==['PROFILE_PACK','SKILL_PACK']; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); r=result(root,[],status='SKIP'); assert r['status']=='SKIP' and r['affected_packs']==[]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); r=result(root,[],status='FAIL'); assert r['status']=='FAIL' and r['blocking_codes']==['UPSTREAM_DISCOVERY_FAILED']; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); make_validator(root,'profiles/a',"print('ok')")
    dr={'status':'PASS','base_sha':BASE,'head_sha':'c'*40,'affected_packs':[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}],'validators_executed':False}
    r=mod.execute_pack_checks(repo_root=root,validation_contract=VALIDATION,discovery_contract=DISCOVERY,discovery_result=dr,base_sha=BASE,head_sha=HEAD,verify_git=False)
    assert r['blocking_codes']==['DISCOVERY_HEAD_SHA_MISMATCH']; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); r=result(root,[{'pack_type':'OTHER','pack_root':'profiles/a','exists_at_head':True}]); assert r['blocking_codes']==['DISCOVERY_PACK_TYPE_UNKNOWN']; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a/nested','exists_at_head':True}]); assert r['blocking_codes']==['DISCOVERY_PACK_ROOT_NOT_AUTHORIZED']; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/gone','exists_at_head':False}]); assert 'PACK_ROOT_MISSING' in r['blocking_codes'][0]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); (root/'profiles/a').mkdir(parents=True); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}]); assert 'PACK_VALIDATOR_MISSING' in r['blocking_codes'][0]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); p=root/'profiles/a/validators'; p.mkdir(parents=True); target=root/'outside.py'; target.write_text("print('ok')"); os.symlink(target,p/'validate_pack.py')
    r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}]); assert 'PACK_VALIDATOR_SYMLINKED' in r['blocking_codes'][0]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); make_validator(root,'profiles/a',"raise SystemExit(3)"); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}]); assert 'PACK_LOCAL_VALIDATOR_FAILED' in r['blocking_codes'][0]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); make_validator(root,'profiles/a',"import time; time.sleep(2)"); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}],timeout_seconds=1); assert 'PACK_LOCAL_VALIDATOR_TIMEOUT' in r['blocking_codes'][0]; checks+=1

with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp); make_validator(root,'profiles/a',"print('ok')"); r=result(root,[{'pack_type':'PROFILE_PACK','pack_root':'profiles/a','exists_at_head':True}]);
    assert all(r[k] is False for k in ['runtime_authorized','git_write_authorized','db_write_authorized','deployment_authorized','production_authorized','semantic_quality_review_authorized']); checks+=1

assert checks==13
print('PASS_PACK_VALIDATION_EXECUTE_PACK_CHECKS=13/13')
