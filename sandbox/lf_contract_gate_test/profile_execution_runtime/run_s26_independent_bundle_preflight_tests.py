#!/usr/bin/env python3
from __future__ import annotations
import json, os, tempfile
from pathlib import Path
from s26_independent_bundle_preflight import csha, fsha, validate


def writej(root, name, obj):
    p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(obj,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')

def manifest(root, case_id, artifact_sha):
    files=[]
    for p in sorted(root.rglob('*')):
        if p.is_file() and p.name!='bundle_manifest.json':
            files.append({'path':str(p.relative_to(root)).replace(os.sep,'/'),'bytes':p.stat().st_size,'sha256':fsha(p)})
    writej(root,'bundle_manifest.json',{'bundle_version':'TEST','review_case_id':case_id,'artifact_canonical_sha256':artifact_sha,'manifest_scope':'all bundle files except bundle_manifest.json itself','file_count':len(files),'files':files})

def base(root):
    artifact={'composer_payload':{'title':'Historial'}}; artifact_sha=csha(artifact); case='CASE-1'
    writej(root,'artifact_payload.json',artifact)
    writej(root,'review_case.json',{'review_case_id':case,'artifact_canonical_sha256':artifact_sha,'review_scope_policy_ref':'bundle://review_scope_policy.json'})
    scope={'schema':'SCOPE','review_case_id':case,'artifact_canonical_sha256':artifact_sha,'review_scope':'FROZEN_ARTIFACT_SEMANTIC_VISUAL_QUALITY'}; scope['policy_sha256']=csha(scope); writej(root,'review_scope_policy.json',scope)
    writej(root,'producer_validation_receipt.json',{'negative_regressions':{'matrix':'3/3','a':True,'b':True,'c':True}})
    writej(root,'evidence.json',{'ref':'bundle://artifact_payload.json'})
    for rel in ('validators/validate_gate_bundle.py','validators/validate_routing.py','validators/trusted_ref_resolver.py','evals/quality_gate_adversarial.py'):
        p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('# test\n',encoding='utf-8')
    manifest(root,case,artifact_sha)
    return artifact_sha

def run_case(name, mutate, expected_code=None):
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); artifact_sha=base(root); mutate(root,artifact_sha)
        if name not in {'extra_file','bytecode'}:
            review=json.loads((root/'review_case.json').read_text()); manifest(root,review['review_case_id'],csha(json.loads((root/'artifact_payload.json').read_text())))
        errors=validate(root)
        if expected_code is None:
            assert errors==[],(name,errors)
        else:
            assert any(e.startswith(expected_code) for e in errors),(name,expected_code,errors)
        print('PASS',name)

def noop(root,sha): pass
def stale_scope(root,sha):
    d=json.loads((root/'review_scope_policy.json').read_text()); d['review_case_id']='OLD'; d['policy_sha256']=csha({k:v for k,v in d.items() if k!='policy_sha256'}); writej(root,'review_scope_policy.json',d)
def missing_ref(root,sha): writej(root,'evidence.json',{'ref':'bundle://prior_run_input.txt'})
def missing_machinery(root,sha): (root/'validators/validate_gate_bundle.py').unlink()
def regression_count(root,sha): writej(root,'producer_validation_receipt.json',{'negative_regressions':{'matrix':'4/4','a':True,'b':True,'c':True}})
def extra_file(root,sha): (root/'unmanifested.txt').write_text('x',encoding='utf-8')
def bytecode(root,sha):
    p=root/'validators/__pycache__/x.cpython-313.pyc'; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(b'pyc')

run_case('base',noop,None)
run_case('stale_scope',stale_scope,'REVIEW_SCOPE_CASE_MISMATCH')
run_case('missing_ref',missing_ref,'BUNDLE_REF_UNRESOLVED')
run_case('missing_machinery',missing_machinery,'PASS_RECONCILIATION_MACHINERY_MISSING')
run_case('regression_count',regression_count,'NEGATIVE_REGRESSION_COUNT_MISMATCH')
run_case('extra_file',extra_file,'MANIFEST_SET_MISMATCH')
run_case('bytecode',bytecode,'DISPOSABLE_BYTECODE_IN_BUNDLE')
print('S26_INDEPENDENT_BUNDLE_PREFLIGHT_TESTS_PASS=7/7')
