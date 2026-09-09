#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, re, sys
from pathlib import Path

MACHINERY = (
    'validators/validate_gate_bundle.py',
    'validators/validate_routing.py',
    'validators/trusted_ref_resolver.py',
    'evals/quality_gate_adversarial.py',
)
MATRIX_RE = re.compile(r'^(\d+)/(\d+)$')


def csha(v):
    return hashlib.sha256(json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def fsha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def load(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))

def _walk_refs(value, path='$'):
    if isinstance(value, dict):
        for k, v in value.items():
            yield from _walk_refs(v, f'{path}.{k}')
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from _walk_refs(v, f'{path}[{i}]')
    elif isinstance(value, str) and value.startswith('bundle://'):
        yield path, value

def validate(root: Path):
    root = root.resolve()
    errors=[]
    def req(cond, code, detail=''):
        if not cond: errors.append(code + (':' + str(detail) if detail else ''))
    for name in ('review_case.json','review_scope_policy.json','artifact_payload.json','producer_validation_receipt.json','bundle_manifest.json'):
        req((root/name).is_file(),'BUNDLE_REQUIRED_FILE_MISSING',name)
    if errors: return errors
    review=load(root/'review_case.json'); scope=load(root/'review_scope_policy.json'); artifact=load(root/'artifact_payload.json'); pv=load(root/'producer_validation_receipt.json'); man=load(root/'bundle_manifest.json')
    artifact_sha=csha(artifact)
    req(scope.get('review_case_id')==review.get('review_case_id'),'REVIEW_SCOPE_CASE_MISMATCH',f"{scope.get('review_case_id')}!={review.get('review_case_id')}")
    req(scope.get('artifact_canonical_sha256')==artifact_sha==review.get('artifact_canonical_sha256'),'REVIEW_SCOPE_ARTIFACT_MISMATCH')
    if 'policy_sha256' in scope:
        req(scope['policy_sha256']==csha({k:v for k,v in scope.items() if k!='policy_sha256'}),'REVIEW_SCOPE_POLICY_SHA_MISMATCH')
    for p in sorted(root.rglob('*.json')):
        if p.name=='bundle_manifest.json':
            continue
        try: obj=load(p)
        except Exception as exc:
            errors.append(f'JSON_PARSE_FAIL:{p.relative_to(root)}:{type(exc).__name__}'); continue
        for jpath, ref in _walk_refs(obj):
            rel=ref[len('bundle://'):].split('#',1)[0]
            req(bool(rel) and not rel.startswith('/') and '..' not in Path(rel).parts,'BUNDLE_REF_UNSAFE',f'{p.relative_to(root)}:{jpath}:{ref}')
            if rel and not rel.startswith('/') and '..' not in Path(rel).parts:
                req((root/rel).is_file(),'BUNDLE_REF_UNRESOLVED',f'{p.relative_to(root)}:{jpath}:{ref}')
    scope_name=scope.get('review_scope')
    semantic_only = scope_name == 'SEMANTIC_VISUAL_QUALITY_ONLY'
    if not semantic_only:
        for rel in MACHINERY:
            req((root/rel).is_file(),'PASS_RECONCILIATION_MACHINERY_MISSING',rel)
    neg=pv.get('negative_regressions')
    req(isinstance(neg,dict),'NEGATIVE_REGRESSIONS_OBJECT_MISSING')
    if isinstance(neg,dict):
        matrix=neg.get('matrix')
        m=MATRIX_RE.fullmatch(matrix or '')
        req(m is not None,'NEGATIVE_REGRESSION_MATRIX_INVALID',matrix)
        named=[k for k,v in neg.items() if k!='matrix' and isinstance(v,bool) and v]
        if m:
            n,d=map(int,m.groups())
            req(n==d==len(named),'NEGATIVE_REGRESSION_COUNT_MISMATCH',f'matrix={matrix},named={len(named)}')
    files=man.get('files'); req(isinstance(files,list),'MANIFEST_FILES_INVALID')
    if isinstance(files,list):
        listed={item.get('path') for item in files if isinstance(item,dict)}
        actual={str(p.relative_to(root)).replace(os.sep,'/') for p in root.rglob('*') if p.is_file() and p.name!='bundle_manifest.json'}
        req(man.get('file_count')==len(files)==len(listed),'MANIFEST_FILE_COUNT_MISMATCH',f"declared={man.get('file_count')},entries={len(files)},unique={len(listed)}")
        req(listed==actual,'MANIFEST_SET_MISMATCH',f'missing={sorted(actual-listed)},extra={sorted(listed-actual)}')
        bad=sorted(x for x in actual if '__pycache__/' in x or x.endswith('.pyc'))
        req(not bad,'DISPOSABLE_BYTECODE_IN_BUNDLE',bad)
        for item in files:
            if not isinstance(item,dict): continue
            rel=item.get('path'); p=root/rel if isinstance(rel,str) else None
            if p and p.is_file():
                req(item.get('bytes')==p.stat().st_size,'MANIFEST_BYTES_MISMATCH',rel)
                req(item.get('sha256')==fsha(p),'MANIFEST_SHA_MISMATCH',rel)
    req(man.get('review_case_id')==review.get('review_case_id'),'MANIFEST_REVIEW_CASE_MISMATCH')
    req(man.get('artifact_canonical_sha256')==artifact_sha,'MANIFEST_ARTIFACT_MISMATCH')
    return errors

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,required=True); args=ap.parse_args()
    errors=validate(args.root)
    print(json.dumps({'valid':not errors,'errors':errors},indent=2,ensure_ascii=False))
    return 0 if not errors else 1
if __name__=='__main__': raise SystemExit(main())
