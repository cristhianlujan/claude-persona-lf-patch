#!/usr/bin/env python3
import importlib.util
import json
import os
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[2]
RUNTIME_DIR=REPO/'sandbox/lf_contract_gate_test/profile_execution_runtime'
if str(RUNTIME_DIR) not in sys.path: sys.path.insert(0,str(RUNTIME_DIR))
p=RUNTIME_DIR/'github_actions_local_runtime.py'
s=importlib.util.spec_from_file_location('persistent_boundary_runtime',p)
m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m)
contract=json.loads((ROOT/'PERSISTENT_CPU_RUNTIME_CONTRACT_V1_20260902.json').read_text(encoding='utf-8'))
assert contract['status']=='IMPLEMENTED_DETERMINISTICALLY_TESTED_NO_REAL_INFERENCE'
assert contract['current_github_adapter_reusable_on_persistent_host'] is False
assert contract['github_adapter_blocker_code']=='ZERO_COST_GITHUB_RUNNER_PRECONDITION_FAILED'
assert contract['real_host_assets_observed'] is False
assert contract['real_host_readiness']=='NOT_EXECUTED'
assert contract['real_model_inference']=='NOT_EXECUTED'
assert contract['semantic_after_status']=='NOT_EXECUTED'
assert contract['implementation']['adapter_verifier_gate']=='10/10 PASS'
assert contract['implementation']['request_wiring_gate']=='8/8 PASS'
req=contract['required_persistent_cpu_contract']
assert req['same_pinned_llama_source_commit']==m.LLAMA_SOURCE_COMMIT
assert req['same_model_sha256']==m.MODEL_SHA256
assert req['same_mmproj_sha256']==m.MMPROJ_SHA256
assert req['timeout_increase_forbidden'] is True
keys=['GITHUB_ACTIONS','RUNNER_OS','RUNNER_ARCH','GITHUB_REPOSITORY','LF_REPOSITORY_VISIBILITY','LF_RUNNER_LABEL','LF_LLAMA_SOURCE_COMMIT']
old={k:os.environ.get(k) for k in keys}
for k in keys: os.environ.pop(k,None)
try:
 try:
  m._require_zero_cost_runner()
  raise AssertionError('github adapter accepted persistent host without GitHub runner identity')
 except Exception as exc:
  assert getattr(exc,'code',None)=='ZERO_COST_GITHUB_RUNNER_PRECONDITION_FAILED',repr(exc)
finally:
 for k,v in old.items():
  if v is None: os.environ.pop(k,None)
  else: os.environ[k]=v
print('PERSISTENT_CPU_RUNTIME_BOUNDARY_V3_PASS 13/13')
