#!/usr/bin/env python3
"""Verify exact P0 inventory, pinned content and executable gates including visual-quality V2."""
from __future__ import annotations
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
MANIFEST=ROOT/'manifest.candidate.json'
EXT_MANIFEST=ROOT/'manifest.visual-quality-v2.json'
ARCHITECTURE_SHA256='a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531'
CANONICALIZER_SHA256='99952f4a1c0819bfc6a7488bea595b43ff31697a0c5ffe034c3e7ea76cde930f'
SCRIPT_GATES=[['validate_p0_contracts.py','--self-test'],['admit_p0_image.py','--self-test'],['validate_p0_security.py','--self-test'],['validate_p0_visual_output.py','--self-test'],['validate_p0_judge.py','--self-test'],['validate_p0_human_binding.py','--self-test'],['validate_p0_j02_handoff.py','--self-test'],['adapt_p0_to_screen_decomposer.py','--self-test'],['smoke_p0_j02.py'],['run_p0_visual_worker.py','--self-test'],['build_p0_review_evidence_packet.py','--self-test'],['report_p0_metric_denominators.py','--self-test'],['report_p0_metric_denominators.py'],['audit_p0_handoff_compliance.py','--self-test']]
EVAL_GATES=['p0_machine_visual_quality_negative_suite.py','p0_machine_visual_quality_negative_suite_v2.py','p0_visual_quality_runtime_regression_suite.py','p0_blind_forward_adversarial_test.py']
def sha256(path:Path)->str:return hashlib.sha256(path.read_bytes()).hexdigest()
def git_blob_sha(path:Path)->str:
 data=path.read_bytes();return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def declared_rows(base:dict,ext:dict)->dict[str,dict]:
 rows={r['path']:r for r in base.get('files',[]) if isinstance(r,dict) and isinstance(r.get('path'),str)}
 for r in ext.get('files',[]):
  if isinstance(r,dict) and isinstance(r.get('path'),str):rows[r['path']]=r
 return rows
def main()->int:
 base=json.loads(MANIFEST.read_text());ext=json.loads(EXT_MANIFEST.read_text());declared=declared_rows(base,ext)
 actual=[];symlinks=[]
 for path in ROOT.rglob('*'):
  if path in {MANIFEST,EXT_MANIFEST} or path.is_dir():continue
  rel=path.relative_to(ROOT).as_posix()
  if path.is_symlink():symlinks.append(rel)
  elif '__pycache__' not in path.parts and not path.name.endswith('.pyc'):actual.append(rel)
 actual_set=set(actual);declared_set=set(declared);mismatches=[]
 for rel in sorted(actual_set & declared_set):
  path=ROOT/rel;row=declared[rel];ok=False
  if isinstance(row.get('sha256'),str):ok=sha256(path)==row['sha256']
  elif isinstance(row.get('git_blob_sha'),str):ok=git_blob_sha(path)==row['git_blob_sha']
  if isinstance(row.get('bytes'),int):ok=ok and path.stat().st_size==row['bytes']
  if not ok:mismatches.append(rel)
 env=dict(os.environ);env['PYTHONDONTWRITEBYTECODE']='1';gate_results=[]
 for script,*args in SCRIPT_GATES:
  p=subprocess.run([sys.executable,str(ROOT/'scripts'/script),*args],text=True,capture_output=True,env=env)
  gate_results.append({'gate':'scripts/'+script,'exit_code':p.returncode,'last_line':(p.stdout.strip().splitlines()[-1] if p.stdout.strip() else p.stderr.strip()[-500:])})
 for script in EVAL_GATES:
  p=subprocess.run([sys.executable,str(ROOT/'evals'/script)],text=True,capture_output=True,env=env)
  gate_results.append({'gate':'evals/'+script,'exit_code':p.returncode,'last_line':(p.stdout.strip().splitlines()[-1] if p.stdout.strip() else p.stderr.strip()[-500:])})
 canonicalizer=ROOT/'P0_RFC8785_CANONICALIZER_v1.1.mjs'
 checks={'inventory_exact':actual_set==declared_set,'hashes_exact':not mismatches,'symlink_count_zero':not symlinks,'architecture_source_pinned':base.get('architecture_source_sha256')==ARCHITECTURE_SHA256,'canonicalizer_identity_exact':canonicalizer.is_file() and sha256(canonicalizer)==CANONICALIZER_SHA256,'visual_quality_extension_version':ext.get('schema_version')=='p0-visual-quality-inventory-extension/v1','p0_5_remains_separate':ext.get('p0_5_state')=='BLOCKED_BENCHMARK','all_gates_pass':all(r['exit_code']==0 for r in gate_results)}
 passed=all(checks.values());report={'result':'PASS_WITH_EVIDENCE' if passed else 'BLOCKED','checks':checks,'declared_file_count':len(declared_set),'actual_file_count':len(actual_set),'missing':sorted(declared_set-actual_set),'unexpected':sorted(actual_set-declared_set),'hash_mismatches':mismatches,'symlinks':symlinks,'gate_results':gate_results};print(json.dumps(report,sort_keys=True));return 0 if passed else 2
if __name__=='__main__':raise SystemExit(main())
