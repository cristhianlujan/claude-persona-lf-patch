#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, os, sys, tempfile
from pathlib import Path
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parent; REPO=ROOT.parents[2]; RUNTIME=REPO/'sandbox/lf_contract_gate_test/profile_execution_runtime'
if str(RUNTIME) not in sys.path: sys.path.insert(0,str(RUNTIME))
from profile_runtime_runner import execute_profile_runtime, RuntimeExecutionBlocked
p=RUNTIME/'persistent_cpu_local_runtime.py'; s=importlib.util.spec_from_file_location('persistent_cpu_local_runtime_v3',p); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as td:
 w=Path(td); cli=w/'llama-cli'; model=w/'model.gguf'; mm=w/'mmproj.gguf'; image=w/'input.png'
 cli.write_text('#!/bin/sh\nexit 0\n'); cli.chmod(0o755); model.write_bytes(b'model'); mm.write_bytes(b'mmproj'); image.write_bytes(b'png')
 schema=w/'profiles/p/schemas/runtime_output.schema.json'; schema.parent.mkdir(parents=True); schema.write_text('{"type":"object"}')
 assets={'LF_LLAMA_CLI_PATH':cli,'LF_MODEL_PATH':model,'LF_MMPROJ_PATH':mm}
 old_required=m.base._required_asset; old_model=m.base.MODEL_SHA256; old_mm=m.base.MMPROJ_SHA256
 old_runtime_id=os.environ.get('LF_PERSISTENT_RUNTIME_ID'); old_scope=os.environ.get('LF_PERSISTENT_RUNTIME_SCOPE'); old_source=os.environ.get('LF_LLAMA_SOURCE_COMMIT')
 m.base.MODEL_SHA256=m.base._sha256_file(model); m.base.MMPROJ_SHA256=m.base._sha256_file(mm); m.base._required_asset=lambda name,expected_sha=None: assets[name]
 os.environ['LF_PERSISTENT_RUNTIME_ID']='sandbox-persistent-cpu-01'
 observed={}
 def fake_run(command,**kwargs):
  observed['command']=list(command); out=Path(command[command.index('-o')+1]); out.write_text('{"decision":"ok"}\n'); return SimpleNamespace(returncode=0,stdout='',stderr='')
 old_run=m.subprocess.run; m.subprocess.run=fake_run
 try:
  os.environ.pop('LF_PERSISTENT_RUNTIME_SCOPE',None)
  try: m._require_isolated_scope(); raise AssertionError('missing isolated scope accepted')
  except RuntimeExecutionBlocked as exc: assert exc.code=='PERSISTENT_RUNTIME_SCOPE_NOT_ISOLATED'
  os.environ['LF_PERSISTENT_RUNTIME_SCOPE']=m.ALLOWED_SCOPE
  os.environ['LF_LLAMA_SOURCE_COMMIT']=m.base.LLAMA_SOURCE_COMMIT
  adapter=m.PersistentCpuLlamaCppAdapter(work_dir=w,image_path=image,image_sha256=m.base._sha256_file(image))
  verifier=m.PersistentCpuLlamaCppVerifier(expected_image_path=image,expected_image_sha256=m.base._sha256_file(image))
  package=execute_profile_runtime(execution_id='PERSISTENT_TEST_1',profile_code='P',profile_slug='p',profile_sources=[{'ref':'profiles/p/profile.md','content':'Return governed JSON.'}],input_literal='Review exact artifact.',adapter=adapter,attestation_verifier=verifier)
  receipt=package['receipt']; att=receipt['runtime_attestation']
  assert att['provider']==m.PROVIDER and att['runtime_id']=='sandbox-persistent-cpu-01'
  assert att['runtime_scope']==m.ALLOWED_SCOPE and att['llama_source_commit']==m.base.LLAMA_SOURCE_COMMIT
  assert att['model_sha256']==m.base.MODEL_SHA256 and att['mmproj_sha256']==m.base.MMPROJ_SHA256
  assert att['input_image_sha256']==m.base._sha256_file(image)
  assert att['structured_output_schema_ref']=='profiles/p/schemas/runtime_output.schema.json'
  assert '-jf' in observed['command'] and '--image' in observed['command']
  assert package['runtime_attestation_verification']['verified'] is True
  try: m.PersistentCpuLlamaCppAdapter(work_dir=w,timeout_seconds=901); raise AssertionError('timeout increase accepted')
  except RuntimeExecutionBlocked as exc: assert exc.code=='PERSISTENT_RUNTIME_TIMEOUT_INCREASE_FORBIDDEN'
  del os.environ['LF_PERSISTENT_RUNTIME_ID']
  try: m._runtime_id(); raise AssertionError('missing runtime id accepted')
  except RuntimeExecutionBlocked as exc: assert exc.code=='PERSISTENT_RUNTIME_ID_MISSING'
 finally:
  m.subprocess.run=old_run; m.base._required_asset=old_required; m.base.MODEL_SHA256=old_model; m.base.MMPROJ_SHA256=old_mm
  if old_runtime_id is None: os.environ.pop('LF_PERSISTENT_RUNTIME_ID',None)
  else: os.environ['LF_PERSISTENT_RUNTIME_ID']=old_runtime_id
  if old_scope is None: os.environ.pop('LF_PERSISTENT_RUNTIME_SCOPE',None)
  else: os.environ['LF_PERSISTENT_RUNTIME_SCOPE']=old_scope
  if old_source is None: os.environ.pop('LF_LLAMA_SOURCE_COMMIT',None)
  else: os.environ['LF_LLAMA_SOURCE_COMMIT']=old_source
print('PERSISTENT_CPU_LOCAL_RUNTIME_V3_PASS 13/13')
