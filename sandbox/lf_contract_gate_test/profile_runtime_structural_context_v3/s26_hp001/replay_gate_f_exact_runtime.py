#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
PKG=ROOT/'services/profile_runtime_api'
STRUCT=ROOT/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3'
if str(PKG) not in sys.path: sys.path.insert(0,str(PKG))
if str(STRUCT) not in sys.path: sys.path.insert(0,str(STRUCT))
from profile_runtime_api.settings import Settings
from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.models import ProfileTask
CANDIDATE='d8c10954d5a6058ffdde7f4b520efcbabf50d180'
EXPECTED_MATERIALIZED='5d938ada46cdaf809ad38791d3c9b59f8c9f6134d0577cbca2f56ac4bf71c3a7'
EXPECTED_MODEL='45b130b396abb690095cb6b64c1bf23b4a046a49c904aee1436ff0a46b450b0b'
EXPECTED_TYPED='24c3e3c60e609a2dc2d55703c624364c9438d4057da13185288a3f537c16ba72'
REQ=HERE/'gate_f_exact_request.json'; MODEL=HERE/'gate_f_exact_model_output.json'; EVID=HERE/'gate_f_exact_runtime_evidence.json'; OBS=HERE/'gate_f_runtime_observation.json'; FOUT=HERE/'gate_f_output.json'; QDP=ROOT/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/test_s26_quality_depth_performance.py'; CONTRACT=HERE/'quality_depth_performance_contract.json'; UI=ROOT/'profiles/ui_architect/validators/validate_ui_architect_output.py'; BOUND=ROOT/'profiles/ui_architect/validators/validate_composer_payload_boundary.py'
def sha_bytes(b): return hashlib.sha256(b).hexdigest()
def sha(p): return sha_bytes(p.read_bytes())
def load(p):
    x=json.loads(p.read_text(encoding='utf-8'))
    if not isinstance(x,dict): raise RuntimeError('NOT_OBJECT:'+p.name)
    return x
def mod(p,n):
    s=importlib.util.spec_from_file_location(n,p)
    if s is None or s.loader is None: raise RuntimeError('MODULE_LOAD_FAILED:'+str(p))
    m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def main():
    ev=load(EVID); req=load(REQ); f=load(FOUT); obs=load(OBS)
    if ev.get('candidate_source_sha')!=CANDIDATE: raise RuntimeError('REPLAY_SOURCE_SHA_MISMATCH')
    if sha(MODEL)!=EXPECTED_MODEL: raise RuntimeError('REPLAY_MODEL_RAW_SHA_MISMATCH')
    if ev.get('runtime',{}).get('runtime_typed_context_sha256')!=EXPECTED_TYPED: raise RuntimeError('REPLAY_TYPED_CONTEXT_SHA_MISMATCH')
    diff=subprocess.run(['git','diff','--quiet',CANDIDATE,'--','services/profile_runtime_api','profiles/ui_architect'],cwd=ROOT)
    if diff.returncode!=0: raise RuntimeError('REPLAY_RUNTIME_OR_PROFILE_SOURCE_DRIFT')
    with tempfile.TemporaryDirectory(prefix='s26-gate-f-replay-') as state:
        settings=Settings(repo_root=ROOT,state_dir=Path(state),api_token='replay-only',source_sha=CANDIDATE)
        engine=ProfileRuntimeEngine(settings); task=ProfileTask.model_validate(req['profile']); model_raw=MODEL.read_text(encoding='utf-8')
        materialized, meta=engine._materialize_runtime_output(task=task,model_raw_output=model_raw,governed_receipt={'runtime_typed_context_sha256':EXPECTED_TYPED})
    if sha_bytes(materialized.encode('utf-8'))!=EXPECTED_MATERIALIZED: raise RuntimeError('REPLAY_MATERIALIZED_SHA_MISMATCH')
    data=json.loads(materialized); ui=mod(UI,'s26_gate_f_ui'); bound=mod(BOUND,'s26_gate_f_bound'); qdp=mod(QDP,'s26_gate_f_qdp')
    if ui.validate(data): raise RuntimeError('REPLAY_UI_VALIDATOR_FAILED')
    if bound.validate(data): raise RuntimeError('REPLAY_COMPOSER_BOUNDARY_FAILED')
    qd=qdp.evaluate_quality_depth(data,load(CONTRACT))
    if not qd['quality']['pass']: raise RuntimeError('REPLAY_QUALITY_FAILED')
    if not qd['depth']['pass']: raise RuntimeError('REPLAY_DEPTH_FAILED')
    if f.get('status')!='PASS' or f.get('decision',{}).get('next_gate_authorized') is not True: raise RuntimeError('REPLAY_GATE_F_NOT_PASS')
    if f.get('runtime_observation',{}).get('sha256')!=sha(OBS): raise RuntimeError('REPLAY_OBSERVATION_BINDING_MISMATCH')
    if f.get('runtime_observation',{}).get('exact_runtime_evidence_sha256')!=sha(EVID): raise RuntimeError('REPLAY_EVIDENCE_BINDING_MISMATCH')
    if obs.get('exact_runtime_evidence',{}).get('sha256')!=sha(EVID): raise RuntimeError('REPLAY_OBSERVATION_EVIDENCE_MISMATCH')
    perf=ev.get('performance') or {}
    if perf.get('status')!='PASS' or float(perf.get('profile_elapsed_ms',1e18))>120000 or float(perf.get('model_generation_elapsed_ms',1e18))>120000: raise RuntimeError('REPLAY_PERFORMANCE_BUDGET_FAILED')
    print(json.dumps({'schema':'S26_HP001_GATE_F_EXACT_REPLAY_V1','result':'PASS','candidate_source_sha':CANDIDATE,'model_raw_output_sha256':EXPECTED_MODEL,'materialized_output_sha256':EXPECTED_MATERIALIZED,'semantic_transport':meta.get('semantic_transport'),'quality':'PASS','depth':'PASS','gate_f':'PASS','network_calls':0,'production_effect':False,'independent_semantic_review_performed':False,'claim_ceiling':'GATE_F_REPLAY_VERIFIED_PENDING_INDEPENDENT_REVIEW_NOT_GOLDEN'},sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
