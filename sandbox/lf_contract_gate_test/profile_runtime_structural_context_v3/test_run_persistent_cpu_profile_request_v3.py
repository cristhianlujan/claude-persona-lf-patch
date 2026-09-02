#!/usr/bin/env python3
from __future__ import annotations
import base64, hashlib, importlib.util, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent; REPO=ROOT.parents[2]; RUNTIME=REPO/'sandbox/lf_contract_gate_test/profile_execution_runtime'
if str(RUNTIME) not in sys.path: sys.path.insert(0,str(RUNTIME))
from validate_profile_execution import canonical_json_sha256, sha256_text
p=RUNTIME/'run_persistent_cpu_profile_request.py'; s=importlib.util.spec_from_file_location('run_persistent_cpu_profile_request_v3',p); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m)
class FakeAdapter:
 adapter_id='persistent-cpu-test-real-boundary'; is_test_double=False
 def __init__(self,**kwargs): self.kwargs=kwargs
 def execute(self,request):
  return {'response_type':'PROFILE_RUNTIME_RESPONSE_V1','raw_output':'{"decision":"ok"}','runtime_attestation':{'provider':'local_llama_cpp_persistent_cpu','model_id':'pinned-test-model','run_id':'persistent:test','attested_at':'2026-09-02T19:00:00Z','adapter_id':self.adapter_id,'request_sha256':request['request_sha256'],'profile_source_sha256':request['profile_source_sha256'],'input_sha256':request['input_sha256'],'operation_code':request['operation_code'],'profile_code':request['profile_code'],'profile_slug':request['profile_slug']}}
class FakeVerifier:
 verifier_id='persistent-cpu-test-verifier'; is_test_double=False
 def __init__(self,**kwargs): self.kwargs=kwargs
 def verify(self,*,request,response,adapter):
  return {'verified':True,'verifier_id':self.verifier_id,'request_sha256':request['request_sha256'],'response_sha256':canonical_json_sha256(response),'evidence_sha256':sha256_text('persistent-test-evidence')}
m.PersistentCpuLlamaCppAdapter=FakeAdapter; m.PersistentCpuLlamaCppVerifier=FakeVerifier
with tempfile.TemporaryDirectory() as td:
 repo=Path(td)/'repo'; work=Path(td)/'work'; work.mkdir(); profile=repo/'profiles/p'; (profile/'schemas').mkdir(parents=True); (profile/'profile.md').write_text('Return governed JSON.'); (profile/'schemas/runtime_output.schema.json').write_text('{"type":"object"}')
 raw=b'exact-private-raster-test'; sha=hashlib.sha256(raw).hexdigest()
 req={'request_id':'r1','operation_code':'EJECUCION_PERFIL_LF','profile_code':'P','profile_slug':'p','input_literal':'Review fixed raster','profile_source_paths':['profiles/p/profile.md'],'input_image_base64':base64.b64encode(raw).decode(),'input_image_media_type':'image/png','input_image_sha256':sha}
 result=m.execute_request(req,repo_root=repo,work_dir=work)
 assert result['status']=='SUCCEEDED' and result['schema']==m.RESULT_SCHEMA
 assert result['runtime_provider']=='local_llama_cpp_persistent_cpu'
 assert result['receipt']['runtime_attestation']['adapter_id']=='persistent-cpu-test-real-boundary'
 assert result['package']['input_image_sha256']==sha
 assert result['runtime_attestation_verification']['verified'] is True
 assert result['raw_output']=='{"decision":"ok"}'
 assert (work/'profiles/p/schemas/runtime_output.schema.json').is_file()
 bad=dict(req); bad['operation_code']='OTHER'
 try: m.execute_request(bad,repo_root=repo,work_dir=work); raise AssertionError('invalid operation accepted')
 except Exception as exc: assert getattr(exc,'code',None)=='QUEUE_OPERATION_CODE_INVALID'
print('RUN_PERSISTENT_CPU_PROFILE_REQUEST_V3_PASS 8/8')
