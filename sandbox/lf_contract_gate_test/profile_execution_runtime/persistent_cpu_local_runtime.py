#!/usr/bin/env python3
"""Persistent CPU llama.cpp adapter for isolated LF profile candidate execution.

Keeps the existing pinned llama/model/mmproj contract but does not require GitHub Actions
runner identity. It performs no network access and expects assets to be preinstalled.
"""
from __future__ import annotations
import os, subprocess, tempfile
from pathlib import Path
from typing import Any

import github_actions_local_runtime as base
from profile_runtime_runner import RESPONSE_TYPE, RuntimeExecutionBlocked
from validate_profile_execution import canonical_json_sha256, sha256_text

ADAPTER_ID='persistent-cpu-llamacpp-qwen25vl-v1'
VERIFIER_ID='persistent-cpu-llamacpp-readback-v1'
PROVIDER='local_llama_cpp_persistent_cpu'
ALLOWED_SCOPE='ISOLATED_CANDIDATE'


def _runtime_id()->str:
 value=os.getenv('LF_PERSISTENT_RUNTIME_ID','').strip()
 if not value:
  raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_ID_MISSING')
 if len(value)>128:
  raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_ID_INVALID')
 return value

def _require_isolated_scope()->str:
 scope=os.getenv('LF_PERSISTENT_RUNTIME_SCOPE','').strip()
 if scope!=ALLOWED_SCOPE:
  raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_SCOPE_NOT_ISOLATED',scope or 'MISSING')
 return scope

def _require_pinned_llama_source()->str:
 observed=os.getenv('LF_LLAMA_SOURCE_COMMIT','').strip()
 if observed!=base.LLAMA_SOURCE_COMMIT:
  raise RuntimeExecutionBlocked('PERSISTENT_LLAMA_SOURCE_COMMIT_MISMATCH',observed or 'MISSING')
 return observed

class PersistentCpuLlamaCppAdapter:
 adapter_id=ADAPTER_ID
 is_test_double=False
 def __init__(self,*,work_dir:Path,image_path:Path|None=None,image_sha256:str|None=None,timeout_seconds:int=900,max_output_tokens:int=2048,context_tokens:int=16384)->None:
  self.work_dir=Path(work_dir).resolve(); self.image_path=image_path; self.image_sha256=image_sha256
  self.timeout_seconds=timeout_seconds; self.max_output_tokens=max_output_tokens; self.context_tokens=context_tokens
  self.asset_paths={}; self.execution_files={}; self.structured_output_schema_path=None
  if timeout_seconds>900: raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_TIMEOUT_INCREASE_FORBIDDEN')
  if (image_path is None)!=(image_sha256 is None): raise RuntimeExecutionBlocked('LOCAL_RUNTIME_IMAGE_BINDING_INCOMPLETE')
  if image_path is not None:
   image_path=Path(image_path).resolve(); self.image_path=image_path
   if not image_path.is_file() or image_path.stat().st_size>base.MAX_IMAGE_BYTES: raise RuntimeExecutionBlocked('LOCAL_RUNTIME_IMAGE_INVALID')
   if base._sha256_file(image_path)!=image_sha256: raise RuntimeExecutionBlocked('LOCAL_RUNTIME_IMAGE_SHA256_MISMATCH')
 def _assets(self):
  _require_isolated_scope(); _require_pinned_llama_source()
  cli=base._required_asset('LF_LLAMA_CLI_PATH')
  model=base._required_asset('LF_MODEL_PATH',base.MODEL_SHA256)
  mmproj=base._required_asset('LF_MMPROJ_PATH',base.MMPROJ_SHA256)
  if not os.access(cli,os.X_OK): raise RuntimeExecutionBlocked('LOCAL_RUNTIME_CLI_NOT_EXECUTABLE')
  self.asset_paths={'llama_cli':cli,'model':model,'mmproj':mmproj}; return self.asset_paths
 def execute(self,request:dict[str,Any])->dict[str,Any]:
  runtime_id=_runtime_id(); assets=self._assets(); source_commit=_require_pinned_llama_source()
  self.structured_output_schema_path=base._resolve_runtime_output_schema(self.work_dir,request['profile_slug'])
  run_dir=Path(tempfile.mkdtemp(prefix='lf-persistent-profile-run-',dir=self.work_dir))
  system_file=run_dir/'system.txt'; input_file=run_dir/'input.txt'; output_file=run_dir/'raw-output.txt'
  system_file.write_text(base._render_profile_instructions(request),encoding='utf-8')
  input_file.write_text(request['input_literal'],encoding='utf-8')
  command=[str(assets['llama_cli']),'-m',str(assets['model']),'-mm',str(assets['mmproj']),'-sysf',str(system_file),'--prompt',request['input_literal'],'-st','--simple-io','--no-display-prompt','--no-show-timings','-co','off','-c',str(self.context_tokens),'-n',str(self.max_output_tokens),'-t','4','--temp','0.2','--top-p','0.9','-s','42','-o',str(output_file)]
  if self.structured_output_schema_path is not None: command.extend(['-jf',str(self.structured_output_schema_path)])
  if self.image_path is not None: command.extend(['--image',str(self.image_path)])
  try:
   completed=subprocess.run(command,cwd=self.work_dir,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=self.timeout_seconds,check=False)
  except subprocess.TimeoutExpired as exc: raise RuntimeExecutionBlocked('LOCAL_RUNTIME_TIMEOUT') from exc
  if completed.returncode!=0: raise RuntimeExecutionBlocked('LOCAL_RUNTIME_PROCESS_FAILED',f'rc={completed.returncode} stderr={completed.stderr[-1500:].replace(chr(10)," ").strip()}')
  if not output_file.is_file(): raise RuntimeExecutionBlocked('LOCAL_RUNTIME_OUTPUT_FILE_MISSING')
  raw=output_file.read_text(encoding='utf-8').strip()
  if not raw: raise RuntimeExecutionBlocked('LOCAL_RUNTIME_OUTPUT_EMPTY')
  self.execution_files={'system':system_file,'input':input_file,'output':output_file}
  att={'provider':PROVIDER,'model_id':base.MODEL_ID,'run_id':f'persistent:{runtime_id}','attested_at':base._utc_now(),'adapter_id':self.adapter_id,'request_sha256':request['request_sha256'],'profile_source_sha256':request['profile_source_sha256'],'input_sha256':request['input_sha256'],'operation_code':request['operation_code'],'profile_code':request['profile_code'],'profile_slug':request['profile_slug'],'runtime_id':runtime_id,'runtime_scope':ALLOWED_SCOPE,'llama_release':base.LLAMA_RELEASE,'llama_source_commit':source_commit,'llama_cli_sha256':base._sha256_file(assets['llama_cli']),'model_sha256':base.MODEL_SHA256,'mmproj_sha256':base.MMPROJ_SHA256,'system_prompt_sha256':base._sha256_file(system_file),'literal_input_file_sha256':base._sha256_file(input_file),'raw_output_file_sha256':base._sha256_file(output_file),'context_tokens':str(self.context_tokens),'max_output_tokens':str(self.max_output_tokens),'network_access_required':'false'}
  if self.structured_output_schema_path is not None:
   att['structured_output_schema_ref']=str(self.structured_output_schema_path.relative_to(self.work_dir)); att['structured_output_schema_sha256']=base._sha256_file(self.structured_output_schema_path)
  if request.get('lf_adapter_source_sha256'): att['lf_adapter_source_sha256']=request['lf_adapter_source_sha256']
  if self.image_path is not None: att['input_image_sha256']=self.image_sha256; att['input_image_size_bytes']=str(self.image_path.stat().st_size)
  return {'response_type':RESPONSE_TYPE,'raw_output':raw,'runtime_attestation':att}

class PersistentCpuLlamaCppVerifier:
 verifier_id=VERIFIER_ID
 is_test_double=False
 def __init__(self,*,expected_image_path:Path|None=None,expected_image_sha256:str|None=None)->None:
  self.expected_image_path=expected_image_path; self.expected_image_sha256=expected_image_sha256
  if (expected_image_path is None)!=(expected_image_sha256 is None): raise RuntimeExecutionBlocked('LOCAL_VERIFIER_IMAGE_BINDING_INCOMPLETE')
 def verify(self,*,request:dict[str,Any],response:dict[str,Any],adapter:Any)->dict[str,Any]:
  if getattr(adapter,'adapter_id',None)!=ADAPTER_ID: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_ADAPTER_MISMATCH')
  att=response.get('runtime_attestation');
  if not isinstance(att,dict): raise RuntimeExecutionBlocked('LOCAL_VERIFIER_ATTESTATION_MISSING')
  if att.get('runtime_id')!=_runtime_id(): raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_ID_MISMATCH')
  if att.get('runtime_scope')!=_require_isolated_scope(): raise RuntimeExecutionBlocked('PERSISTENT_RUNTIME_SCOPE_MISMATCH')
  if att.get('llama_source_commit')!=_require_pinned_llama_source(): raise RuntimeExecutionBlocked('PERSISTENT_LLAMA_SOURCE_COMMIT_MISMATCH')
  assets=getattr(adapter,'asset_paths',{}); files=getattr(adapter,'execution_files',{})
  if set(assets)!={'llama_cli','model','mmproj'} or set(files)!={'system','input','output'}: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_EVIDENCE_PATHS_MISSING')
  expected={'model_sha256':base.MODEL_SHA256,'mmproj_sha256':base.MMPROJ_SHA256,'llama_cli_sha256':att.get('llama_cli_sha256'),'system_prompt_sha256':att.get('system_prompt_sha256'),'raw_output_file_sha256':att.get('raw_output_file_sha256')}
  observed={'model_sha256':base._sha256_file(assets['model']),'mmproj_sha256':base._sha256_file(assets['mmproj']),'llama_cli_sha256':base._sha256_file(assets['llama_cli']),'system_prompt_sha256':base._sha256_file(files['system']),'raw_output_file_sha256':base._sha256_file(files['output'])}
  for key,val in expected.items():
   if observed[key]!=val: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_HASH_MISMATCH',key)
  if sha256_text(files['input'].read_text(encoding='utf-8'))!=request['input_sha256']: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_LITERAL_INPUT_MISMATCH')
  if self.expected_image_path is not None:
   if not Path(self.expected_image_path).is_file() or base._sha256_file(Path(self.expected_image_path))!=self.expected_image_sha256: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_IMAGE_MISMATCH')
   if att.get('input_image_sha256')!=self.expected_image_sha256: raise RuntimeExecutionBlocked('LOCAL_VERIFIER_IMAGE_ATTESTATION_MISMATCH')
  response_sha=canonical_json_sha256(response)
  evidence_sha=sha256_text('|'.join([self.verifier_id,request['request_sha256'],response_sha,observed['system_prompt_sha256'],observed['raw_output_file_sha256'],att['runtime_id'],att['runtime_scope'],att['llama_source_commit']]))
  return {'verified':True,'verifier_id':self.verifier_id,'request_sha256':request['request_sha256'],'response_sha256':response_sha,'evidence_sha256':evidence_sha}
