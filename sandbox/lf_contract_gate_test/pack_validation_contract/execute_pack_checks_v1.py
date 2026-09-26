#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, re, subprocess, sys
from pathlib import Path, PurePosixPath
from typing import Any
SHA40=re.compile(r'^[0-9a-f]{40}$'); MAX_CAPTURE_BYTES=65536; MAX_EXCERPT_CHARS=4096; DEFAULT_TIMEOUT_SECONDS=120; MAX_TIMEOUT_SECONDS=300
class ExecutionError(ValueError): pass

def load_json(path: Path)->dict[str,Any]:
    value=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value,dict): raise ExecutionError('JSON_OBJECT_REQUIRED')
    return value

def sha256_bytes(value:bytes)->str: return hashlib.sha256(value).hexdigest()
def normalize_repo_path(raw:Any)->str:
    if not isinstance(raw,str) or not raw or raw.startswith('/') or '\\' in raw: raise ExecutionError('PATH_INVALID')
    parts=raw.split('/')
    if any(p in {'','.','..'} for p in parts): raise ExecutionError('PATH_INVALID')
    norm=PurePosixPath(raw).as_posix()
    if norm!=raw: raise ExecutionError('PATH_NOT_CANONICAL')
    return norm

def normalize_prefix(raw:Any)->str:
    if not isinstance(raw,str) or not raw.endswith('/'): raise ExecutionError('PREFIX_INVALID')
    return normalize_repo_path(raw[:-1])+'/'

def validate_sha(value:Any,field:str)->str:
    if not isinstance(value,str) or not SHA40.fullmatch(value): raise ExecutionError(f'{field.upper()}_INVALID')
    return value

def allowed_target_roots(validation_contract:dict[str,Any], discovery_contract:dict[str,Any])->dict[str,set[str]]:
    if validation_contract.get('durable_name')!='PACK_VALIDATION_DEFINE_CONTRACT': raise ExecutionError('VALIDATION_CONTRACT_IDENTITY_INVALID')
    if discovery_contract.get('durable_name')!='PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS': raise ExecutionError('DISCOVERY_CONTRACT_IDENTITY_INVALID')
    pack_types=validation_contract.get('pack_types')
    if not isinstance(pack_types,dict) or not pack_types: raise ExecutionError('VALIDATION_PACK_TYPES_MISSING')
    validation_roots={}
    for pack_type,cfg in pack_types.items():
        roots=cfg.get('roots') if isinstance(cfg,dict) else None
        if not isinstance(pack_type,str) or not isinstance(roots,list) or not roots: raise ExecutionError('VALIDATION_PACK_TYPE_INVALID')
        validation_roots[pack_type]={normalize_prefix(r) for r in roots}
    targets={k:set() for k in validation_roots}
    rules=discovery_contract.get('rules')
    if not isinstance(rules,list) or not rules: raise ExecutionError('DISCOVERY_RULES_MISSING')
    for rule in rules:
        if not isinstance(rule,dict): raise ExecutionError('DISCOVERY_RULE_INVALID')
        pt=rule.get('pack_type')
        if pt not in validation_roots: raise ExecutionError('DISCOVERY_PACK_TYPE_INVALID')
        tr=normalize_prefix(rule.get('target_root'))
        if tr not in validation_roots[pt]: raise ExecutionError('DISCOVERY_TARGET_NOT_AUTHORIZED_BY_VALIDATION_CONTRACT')
        targets[pt].add(tr)
    return targets

def _direct_child_of(path:str,prefix:str)->bool:
    if not path.startswith(prefix): return False
    rem=path[len(prefix):]
    return bool(rem) and '/' not in rem

def validate_discovery_result(discovery_result:dict[str,Any],*,base_sha:str,head_sha:str,targets:dict[str,set[str]])->list[dict[str,Any]]:
    status=discovery_result.get('status')
    if status=='FAIL': raise ExecutionError('UPSTREAM_DISCOVERY_FAILED')
    if status not in {'PASS','SKIP'}: raise ExecutionError('DISCOVERY_STATUS_INVALID')
    if discovery_result.get('base_sha')!=base_sha: raise ExecutionError('DISCOVERY_BASE_SHA_MISMATCH')
    if discovery_result.get('head_sha')!=head_sha: raise ExecutionError('DISCOVERY_HEAD_SHA_MISMATCH')
    if discovery_result.get('validators_executed') is not False: raise ExecutionError('DISCOVERY_BOUNDARY_VIOLATION_VALIDATORS_EXECUTED')
    raw_packs=discovery_result.get('affected_packs')
    if not isinstance(raw_packs,list): raise ExecutionError('DISCOVERY_AFFECTED_PACKS_INVALID')
    if status=='SKIP' and raw_packs: raise ExecutionError('DISCOVERY_SKIP_WITH_PACKS')
    if status=='PASS' and not raw_packs: raise ExecutionError('DISCOVERY_PASS_WITHOUT_PACKS')
    seen=set(); packs=[]
    for raw in raw_packs:
        if not isinstance(raw,dict): raise ExecutionError('DISCOVERY_PACK_INVALID')
        pt=raw.get('pack_type')
        if not isinstance(pt,str) or pt not in targets: raise ExecutionError('DISCOVERY_PACK_TYPE_UNKNOWN')
        root=normalize_repo_path(raw.get('pack_root'))
        if not any(_direct_child_of(root,p) for p in targets[pt]): raise ExecutionError('DISCOVERY_PACK_ROOT_NOT_AUTHORIZED')
        ident=(pt,root)
        if ident in seen: raise ExecutionError('DISCOVERY_DUPLICATE_PACK_IDENTITY')
        seen.add(ident)
        exists=raw.get('exists_at_head')
        if not isinstance(exists,bool): raise ExecutionError('DISCOVERY_EXISTS_AT_HEAD_INVALID')
        packs.append({'pack_type':pt,'pack_root':root,'exists_at_head':exists})
    packs.sort(key=lambda x:(x['pack_type'],x['pack_root']))
    return packs

def verify_git_identity(repo_root:Path,base_sha:str,head_sha:str)->None:
    try:
        observed=subprocess.check_output(['git','-C',str(repo_root),'rev-parse','HEAD'],text=True,stderr=subprocess.STDOUT).strip()
        if observed!=head_sha: raise ExecutionError('REPO_HEAD_SHA_MISMATCH')
        subprocess.run(['git','-C',str(repo_root),'cat-file','-e',f'{base_sha}^{{commit}}'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['git','-C',str(repo_root),'merge-base','--is-ancestor',base_sha,head_sha],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    except ExecutionError: raise
    except (subprocess.CalledProcessError,OSError) as exc: raise ExecutionError('GIT_IDENTITY_VERIFICATION_FAILED') from exc

def resolve_safe_child(repo_root:Path,pack_root:str)->Path:
    repo_root=repo_root.resolve(); candidate=repo_root/pack_root
    if candidate.is_symlink(): raise ExecutionError('PACK_ROOT_SYMLINKED')
    resolved=candidate.resolve()
    try: resolved.relative_to(repo_root)
    except ValueError as exc: raise ExecutionError('PACK_ROOT_ESCAPES_REPOSITORY') from exc
    return resolved

def run_local_validator(pack_path:Path,timeout_seconds:int)->dict[str,Any]:
    validator=pack_path/'validators'/'validate_pack.py'
    if validator.is_symlink(): raise ExecutionError('PACK_VALIDATOR_SYMLINKED')
    if not validator.is_file(): raise ExecutionError('PACK_VALIDATOR_MISSING')
    resolved=validator.resolve()
    try: resolved.relative_to(pack_path)
    except ValueError as exc: raise ExecutionError('PACK_VALIDATOR_ESCAPES_PACK') from exc
    vb=resolved.read_bytes()
    try:
        run=subprocess.run([sys.executable,str(resolved),str(pack_path)],cwd=pack_path,text=False,capture_output=True,timeout=timeout_seconds,env=os.environ.copy())
        out,err=run.stdout or b'',run.stderr or b''
        return {'returncode':run.returncode,'validator_sha256':sha256_bytes(vb),'stdout_sha256':sha256_bytes(out),'stderr_sha256':sha256_bytes(err),'stdout_bytes':len(out),'stderr_bytes':len(err),'stdout_truncated':len(out)>MAX_CAPTURE_BYTES,'stderr_truncated':len(err)>MAX_CAPTURE_BYTES,'stdout_excerpt':out[:MAX_CAPTURE_BYTES].decode('utf-8','replace')[:MAX_EXCERPT_CHARS],'stderr_excerpt':err[:MAX_CAPTURE_BYTES].decode('utf-8','replace')[:MAX_EXCERPT_CHARS]}
    except subprocess.TimeoutExpired as exc:
        out,err=exc.stdout or b'',exc.stderr or b''
        if isinstance(out,str): out=out.encode()
        if isinstance(err,str): err=err.encode()
        return {'returncode':None,'validator_sha256':sha256_bytes(vb),'stdout_sha256':sha256_bytes(out),'stderr_sha256':sha256_bytes(err),'stdout_bytes':len(out),'stderr_bytes':len(err),'stdout_truncated':len(out)>MAX_CAPTURE_BYTES,'stderr_truncated':len(err)>MAX_CAPTURE_BYTES,'stdout_excerpt':out[:MAX_CAPTURE_BYTES].decode('utf-8','replace')[:MAX_EXCERPT_CHARS],'stderr_excerpt':err[:MAX_CAPTURE_BYTES].decode('utf-8','replace')[:MAX_EXCERPT_CHARS],'timeout':True}

def execute_pack_checks(*,repo_root:Path,validation_contract:dict[str,Any],discovery_contract:dict[str,Any],discovery_result:dict[str,Any],base_sha:str,head_sha:str,timeout_seconds:int=DEFAULT_TIMEOUT_SECONDS,verify_git:bool=True)->dict[str,Any]:
    try:
        base_sha=validate_sha(base_sha,'base_sha'); head_sha=validate_sha(head_sha,'head_sha')
        if not isinstance(timeout_seconds,int) or not (1<=timeout_seconds<=MAX_TIMEOUT_SECONDS): raise ExecutionError('TIMEOUT_SECONDS_INVALID')
        repo_root=repo_root.resolve(); targets=allowed_target_roots(validation_contract,discovery_contract)
        packs=validate_discovery_result(discovery_result,base_sha=base_sha,head_sha=head_sha,targets=targets)
        if verify_git: verify_git_identity(repo_root,base_sha,head_sha)
        if not packs:
            return {'status':'SKIP','base_sha':base_sha,'head_sha':head_sha,'affected_packs':[],'checks_executed':[],'blocking_codes':[],'evidence':{'exact_head_verified':verify_git},'runtime_authorized':False,'git_write_authorized':False,'db_write_authorized':False,'deployment_authorized':False,'production_authorized':False,'semantic_quality_review_authorized':False,'handoff':'PROFILE_PACK_VALIDATION_CLEAN_VALIDATOR'}
        results=[]; blocking=[]
        for pack in packs:
            pt,root=pack['pack_type'],pack['pack_root']; pid=f'{pt}:{root}'
            row={'pack_id':pid,'pack_type':pt,'pack_root':root,'validator_ref':f'{root}/validators/validate_pack.py','status':'FAIL','checks_executed':['PACK_ROOT_BOUNDARY'],'blocking_codes':[]}
            try:
                p=resolve_safe_child(repo_root,root)
                if not pack['exists_at_head'] or not p.is_dir(): raise ExecutionError('PACK_ROOT_MISSING')
                row['checks_executed'].append('PACK_VALIDATOR_BOUNDARY')
                ev=run_local_validator(p,timeout_seconds); row['checks_executed'].append('PACK_LOCAL_VALIDATOR'); row['evidence']=ev
                if ev.get('timeout'): raise ExecutionError('PACK_LOCAL_VALIDATOR_TIMEOUT')
                if ev['returncode']!=0: raise ExecutionError('PACK_LOCAL_VALIDATOR_FAILED')
                row['status']='PASS'
            except ExecutionError as exc:
                row['blocking_codes'].append(str(exc)); blocking.append(f'{pid}:{exc}')
            results.append(row)
        return {'status':'PASS' if not blocking else 'FAIL','base_sha':base_sha,'head_sha':head_sha,'affected_packs':results,'checks_executed':sorted({c for r in results for c in r.get('checks_executed',[])}),'blocking_codes':blocking,'evidence':{'exact_head_verified':verify_git,'pack_count':len(results),'pass_count':sum(r['status']=='PASS' for r in results),'fail_count':sum(r['status']=='FAIL' for r in results)},'runtime_authorized':False,'git_write_authorized':False,'db_write_authorized':False,'deployment_authorized':False,'production_authorized':False,'semantic_quality_review_authorized':False,'handoff':'PROFILE_PACK_VALIDATION_CLEAN_VALIDATOR'}
    except (ExecutionError,json.JSONDecodeError,OSError) as exc:
        return {'status':'FAIL','base_sha':base_sha,'head_sha':head_sha,'affected_packs':[],'checks_executed':[],'blocking_codes':[str(exc)],'evidence':{'exact_head_verified':False},'runtime_authorized':False,'git_write_authorized':False,'db_write_authorized':False,'deployment_authorized':False,'production_authorized':False,'semantic_quality_review_authorized':False,'handoff':None}

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('--repo-root',type=Path,default=Path('.')); p.add_argument('--validation-contract',type=Path,required=True); p.add_argument('--discovery-contract',type=Path,required=True); p.add_argument('--discovery-result',type=Path,required=True); p.add_argument('--base-sha',required=True); p.add_argument('--head-sha',required=True); p.add_argument('--timeout-seconds',type=int,default=DEFAULT_TIMEOUT_SECONDS); p.add_argument('--skip-git-identity-check',action='store_true'); a=p.parse_args()
    result=execute_pack_checks(repo_root=a.repo_root,validation_contract=load_json(a.validation_contract),discovery_contract=load_json(a.discovery_contract),discovery_result=load_json(a.discovery_result),base_sha=a.base_sha,head_sha=a.head_sha,timeout_seconds=a.timeout_seconds,verify_git=not a.skip_git_identity_check)
    print(json.dumps(result,sort_keys=True,separators=(',',':'))); return 0 if result['status'] in {'PASS','SKIP'} else 1
if __name__=='__main__': raise SystemExit(main())
