#!/usr/bin/env python3
"""Execute one LF profile request on a pre-provisioned persistent CPU runtime."""
from __future__ import annotations
import argparse, json, sys, tempfile
from pathlib import Path
from typing import Any

import run_zero_cost_profile_request as common
from persistent_cpu_local_runtime import PersistentCpuLlamaCppAdapter, PersistentCpuLlamaCppVerifier
from profile_runtime_runner import RuntimeExecutionBlocked, execute_profile_runtime

RESULT_SCHEMA='LF_PROFILE_RUNTIME_PERSISTENT_CPU_RESULT_V1'

def execute_request(request:dict[str,Any],*,repo_root:Path,work_dir:Path)->dict[str,Any]:
 for key in ('request_id','operation_code','profile_code','profile_slug','input_literal'):
  if not common._nonempty(request.get(key)): raise RuntimeExecutionBlocked('QUEUE_REQUEST_FIELD_MISSING',key)
 if request['operation_code']!='EJECUCION_PERFIL_LF': raise RuntimeExecutionBlocked('QUEUE_OPERATION_CODE_INVALID')
 profile_slug=request['profile_slug']; paths=common._safe_source_paths(profile_slug,request.get('profile_source_paths')); sources=[]
 for relative in paths:
  path=repo_root/relative
  if not path.is_file(): raise RuntimeExecutionBlocked('QUEUE_PROFILE_SOURCE_MISSING',relative)
  content=path.read_text(encoding='utf-8')
  if not content: raise RuntimeExecutionBlocked('QUEUE_PROFILE_SOURCE_EMPTY',relative)
  sources.append({'ref':relative,'content':content})
 adapter_sources=common._safe_adapter_sources(request,repo_root)
 image_path,image_sha=common._materialize_image(request,work_dir)
 common._materialize_runtime_output_schema(profile_slug,repo_root,work_dir)
 adapter=PersistentCpuLlamaCppAdapter(work_dir=work_dir,image_path=image_path,image_sha256=image_sha)
 verifier=PersistentCpuLlamaCppVerifier(expected_image_path=image_path,expected_image_sha256=image_sha)
 package=execute_profile_runtime(execution_id=f"EJECUCION_PERFIL_LF:{request['request_id']}",profile_code=request['profile_code'],profile_slug=profile_slug,profile_sources=sources,input_literal=request['input_literal'],adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False,obligation_manifest=request.get('obligation_manifest'),lf_adapter_sources=adapter_sources)
 package['queue_request_id']=request['request_id']; package['input_image_sha256']=image_sha
 return {'schema':RESULT_SCHEMA,'status':'SUCCEEDED','request_id':request['request_id'],'runtime_provider':package['receipt']['runtime_attestation']['provider'],'runtime_model_id':package['receipt']['runtime_attestation']['model_id'],'raw_output':package['raw_output'],'receipt':package['receipt'],'runtime_attestation_verification':package['runtime_attestation_verification'],'package':package}

def main()->int:
 ap=argparse.ArgumentParser(); ap.add_argument('--request',type=Path,required=True); ap.add_argument('--repo-root',type=Path,default=Path.cwd()); ap.add_argument('--output',type=Path,required=True); a=ap.parse_args()
 work_dir=Path(tempfile.mkdtemp(prefix='lf-persistent-cpu-runtime-'))
 try: request=common._load_request(a.request); result=execute_request(request,repo_root=a.repo_root.resolve(),work_dir=work_dir); rc=0
 except RuntimeExecutionBlocked as exc:
  request_id=None
  try: request_id=common._load_request(a.request).get('request_id')
  except RuntimeExecutionBlocked: pass
  result={'schema':RESULT_SCHEMA,'status':'BLOCKED','request_id':request_id,'error_code':exc.code,'error_detail':exc.detail}; rc=2
 except Exception as exc:
  result={'schema':RESULT_SCHEMA,'status':'FAILED','request_id':None,'error_code':'PERSISTENT_CPU_RUNTIME_UNEXPECTED_EXCEPTION','error_detail':type(exc).__name__}; rc=3
 a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8'); print(f"LF_PROFILE_RUNTIME_STATUS={result['status']}")
 if result.get('error_code'): print(f"LF_PROFILE_RUNTIME_ERROR={result['error_code']}",file=sys.stderr)
 return rc
if __name__=='__main__': raise SystemExit(main())
