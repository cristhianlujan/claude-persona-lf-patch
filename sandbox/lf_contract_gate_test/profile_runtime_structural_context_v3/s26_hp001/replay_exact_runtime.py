#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, json, subprocess, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
PKG_ROOT=ROOT/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3'
if str(PKG_ROOT) not in sys.path: sys.path.insert(0, str(PKG_ROOT))
MANIFEST=HERE/'exact_replay_manifest.json'
QDP=ROOT/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/test_s26_quality_depth_performance.py'
GH=HERE/'gate_g_h_exact.py'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def mod(p,n):
 s=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def main():
 m=json.loads(MANIFEST.read_text(encoding='utf-8'))
 if m.get('schema')!='S26_HP001_EXACT_REPLAY_MANIFEST_V1': raise RuntimeError('EXACT_REPLAY_SCHEMA_INVALID')
 if m.get('independent_review_satisfied_by_replay') is not False: raise RuntimeError('REPLAY_FALSE_INDEPENDENT_REVIEW_CLAIM')
 candidate=m['runtime_candidate_source_sha']
 for name,item in m['artifacts'].items():
  p=ROOT/item['ref']
  if not p.is_file(): raise RuntimeError('REPLAY_ARTIFACT_MISSING:'+name)
  if sha(p)!=item['sha256']: raise RuntimeError('REPLAY_ARTIFACT_SHA_MISMATCH:'+name)
 diff=subprocess.run(['git','diff','--quiet',candidate,'--','services/profile_runtime_api','profiles/ui_architect'],cwd=ROOT)
 if diff.returncode!=0: raise RuntimeError('REPLAY_RUNTIME_OR_PROFILE_SOURCE_DRIFT')
 gh=mod(GH,'s26_exact_gh_replay')
 if gh.main()!=0: raise RuntimeError('REPLAY_G_H_FAILED')
 qdp=mod(QDP,'s26_exact_qdp_replay')
 qdp.OUTPUT=HERE/'gate_f_exact_materialized_output.json'
 if qdp.main()!=0: raise RuntimeError('REPLAY_QDP_FAILED')
 f=json.loads((HERE/'gate_f_output.json').read_text(encoding='utf-8'))
 ev=json.loads((HERE/'gate_f_exact_runtime_evidence.json').read_text(encoding='utf-8'))
 if f.get('status')!='PASS' or f.get('next_gate')!='G_STRUCTURED_OUTPUT' or f.get('decision',{}).get('next_gate_authorized') is not True: raise RuntimeError('REPLAY_GATE_F_INVALID')
 if ev.get('candidate_source_sha')!=candidate or ev.get('outputs',{}).get('materialized_raw_output_sha256')!=sha(HERE/'gate_f_exact_materialized_output.json'): raise RuntimeError('REPLAY_GATE_F_BINDING_INVALID')
 print(json.dumps({'gate':'S26_HP001_EXACT_RUNTIME_REPLAY_V1','result':'PASS','runtime_candidate_source_sha':candidate,'materialized_output_sha256':sha(HERE/'gate_f_exact_materialized_output.json'),'gate_f':'PASS','gate_g':'PASS','gate_h':'PASS','quality_depth_performance':'PASS','runtime_profile_source_identity':True,'network_calls':0,'production_effect':False,'independent_semantic_review_performed':False,'claim_ceiling':'EXACT_RUNTIME_DETERMINISTIC_REPLAY_NOT_INDEPENDENT_REVIEW_NOT_GOLDEN'},sort_keys=True))
 return 0
if __name__=='__main__': raise SystemExit(main())
