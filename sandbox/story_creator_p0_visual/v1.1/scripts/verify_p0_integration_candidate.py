#!/usr/bin/env python3
"""Verify exact P0 inventory across V1/V2/V3/V4, executable gates and legacy readability."""
from __future__ import annotations
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
MANIFEST=ROOT/'manifest.candidate.json'
EXT_MANIFEST=ROOT/'manifest.visual-quality-v2.json'
V3_MANIFEST=ROOT/'manifest.visual-fidelity-v3.json'
V4_MANIFEST=ROOT/'manifest.closed-loop-v4.json'
ARCHITECTURE_SHA256='a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531'
CANONICALIZER_SHA256='99952f4a1c0819bfc6a7488bea595b43ff31697a0c5ffe034c3e7ea76cde930f'
LEGACY_BAD_SHA='c0acd3f52388447958b9f60c839f7f4e289488110654784b9d9f94cfccb8b6ff'
SCRIPT_GATES=[['validate_p0_contracts.py','--self-test'],['admit_p0_image.py','--self-test'],['validate_p0_security.py','--self-test'],['validate_p0_visual_output.py','--self-test'],['validate_p0_judge.py','--self-test'],['validate_p0_human_binding.py','--self-test'],['validate_p0_j02_handoff.py','--self-test'],['adapt_p0_to_screen_decomposer.py','--self-test'],['smoke_p0_j02.py'],['report_p0_metric_denominators.py','--self-test'],['report_p0_metric_denominators.py'],['audit_p0_handoff_compliance.py','--self-test'],['validate_p0_v3_schemas.py'],['verify_p0_v3_manifest.py']]
EVAL_GATES=['p0_machine_visual_quality_negative_suite.py','p0_machine_visual_quality_negative_suite_v2.py','p0_visual_quality_runtime_regression_suite.py','p0_blind_forward_adversarial_test.py','p0_visual_fidelity_v3_suite.py','p0_visual_fidelity_forward_adversarial_v3.py','p0_inferred_parent_reassignment_regression.py']
LEGACY_FILES=['scripts/run_p0_visual_worker.py','scripts/build_p0_review_evidence_packet.py','schemas/human-review-packet.schema.json','evals/p0_real_screen_bad_legacy_regression.json']
def sha256(path:Path)->str:return hashlib.sha256(path.read_bytes()).hexdigest()
def git_blob_sha(path:Path)->str:
 data=path.read_bytes();return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
def declared_rows(*manifests:dict)->dict[str,dict]:
 rows={}
 for manifest in manifests:
  for r in manifest.get('files',[]):
   if isinstance(r,dict) and isinstance(r.get('path'),str):rows[r['path']]=r
 return rows
def legacy_compatibility()->dict:
 existing={rel:(ROOT/rel).is_file() for rel in LEGACY_FILES};reg_path=ROOT/'evals/p0_real_screen_bad_legacy_regression.json';reg={}
 if reg_path.is_file():
  try:reg=json.loads(reg_path.read_text())
  except Exception:reg={}
 checks={'legacy_files_present':all(existing.values()),'legacy_bad_output_identity_preserved':reg.get('legacy_visual_output_sha256')==LEGACY_BAD_SHA,'legacy_not_p0_5_eligible':reg.get('p0_5_denominator_eligible') is False,'legacy_new_challenge_gate_declared':reg.get('new_human_challenge_requires')=='PASS_VISUAL_QUALITY_PLUS_J00_SHA_BINDING'}
 return {'pass':all(checks.values()),'checks':checks,'files':existing,'mode':'HISTORICAL_READBACK_ONLY_NOT_CURRENT_RUNTIME_GATE'}
def main()->int:
 base=json.loads(MANIFEST.read_text());ext=json.loads(EXT_MANIFEST.read_text());v3=json.loads(V3_MANIFEST.read_text());v4=json.loads(V4_MANIFEST.read_text());declared=declared_rows(base,ext,v3,v4)
 actual=[];symlinks=[];manifest_paths={MANIFEST,EXT_MANIFEST,V3_MANIFEST,V4_MANIFEST}
 for path in ROOT.rglob('*'):
  if path in manifest_paths or path.is_dir():continue
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
 canonicalizer=ROOT/'P0_RFC8785_CANONICALIZER_v1.1.mjs';legacy=legacy_compatibility();v4_paths={r.get('path') for r in v4.get('files',[]) if isinstance(r,dict)}
 checks={'inventory_exact':actual_set==declared_set,'hashes_exact':not mismatches,'symlink_count_zero':not symlinks,'architecture_source_pinned':base.get('architecture_source_sha256')==ARCHITECTURE_SHA256,'canonicalizer_identity_exact':canonicalizer.is_file() and sha256(canonicalizer)==CANONICALIZER_SHA256,'visual_quality_extension_version':ext.get('schema_version')=='p0-visual-quality-inventory-extension/v1','visual_fidelity_extension_version':v3.get('schema_version')=='p0-visual-fidelity-manifest/v3','v3_baseline_bound':v3.get('baseline_main_sha')=='26611cad05c2986b367ed55d3f38a395d4a3cc0c','v3_production_not_authorized':v3.get('production_authorized') is False,'v4_inventory_marker_version':v4.get('schema_version')=='p0-closed-loop-manifest-v4/remediation-marker-v1','v4_audit_failure_retained':v4.get('audit_state')=='FAIL_AUDIT_V4','v4_production_not_authorized':v4.get('production_authorized') is False,'v4_exact_blob_inventory':v4.get('inventory_mode')=='EXACT_GIT_BLOB_SHA' and len(v4_paths)==30 and {'scripts/p0_independent_omission_sweep_v4.py','evals/p0_reader_producer_contract_v4.py','evals/p0_grader_producer_field_audit_v4.py'}<=v4_paths,'p0_5_remains_separate':ext.get('p0_5_state')=='BLOCKED_BENCHMARK','legacy_compatibility_readable':legacy['pass'],'all_current_gates_pass':all(r['exit_code']==0 for r in gate_results)}
 passed=all(checks.values());report={'result':'PASS_WITH_EVIDENCE' if passed else 'BLOCKED','checks':checks,'legacy_compatibility':legacy,'declared_file_count':len(declared_set),'actual_file_count':len(actual_set),'missing':sorted(declared_set-actual_set),'unexpected':sorted(actual_set-declared_set),'hash_mismatches':mismatches,'symlinks':symlinks,'gate_results':gate_results};print(json.dumps(report,sort_keys=True));return 0 if passed else 2
if __name__=='__main__':raise SystemExit(main())
