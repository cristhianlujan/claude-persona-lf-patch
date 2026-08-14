#!/usr/bin/env python3
"""Regression matrix for pinned PR93 runtime source gate plus P0 V2/V3/V4 quality gates.

Governed-runtime attestation is intentionally read-only. Dependency provisioning
belongs to the workflow environment and must happen before this script runs.
"""
from __future__ import annotations
import importlib.metadata as md,json,os,shutil,subprocess,sys
from pathlib import Path
import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as candidate
sys.dont_write_bytecode=True

def expect_error(name:str,code:str,changed:list[str],*,branch:str,blobs:dict[str,str],modes:dict[str,str]|None=None,main_merge_verified:bool=False)->None:
 try:candidate.evaluate_controlled_runtime_scope(changed,branch=branch,blob_by_path=blobs,mode_by_path=modes,main_merge_verified=main_merge_verified)
 except candidate.RuntimeScopeError as exc:
  if exc.code!=code:raise SystemExit(f"{name}: expected {code}, got {exc.code}: {exc}")
  print(f"PASS_{name}={code}");return
 raise SystemExit(f"{name}: expected {code}, but scope was accepted")

def attest_p0_visual_test_dependencies(repo_root:Path)->None:
 if os.environ.get('P0_CI_ENGINEERING_REGRESSION') is not None:raise SystemExit('FAIL_P0_CI_ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN')
 if os.environ.get('CI')!='true':
  print('PASS_P0_VISUAL_TEST_DEPENDENCIES=SKIPPED_NON_CI_READ_ONLY_ATTESTATION');return
 config_path=repo_root/'sandbox/story_creator_p0_visual/v1.1/evals/p0-visual-quality-runtime-config.json';config=json.loads(config_path.read_text(encoding='utf-8'))
 if config.get('calibration',{}).get('status')!='GOVERNED_OPERATIONAL_CALIBRATION':raise SystemExit('FAIL_P0_VISUAL_GOVERNED_CALIBRATION_STATUS')
 try:tesseract=subprocess.run(['tesseract','--version'],text=True,capture_output=True,check=True).stdout.splitlines()[0].split()[1]
 except Exception:tesseract='UNAVAILABLE'
 actual={}
 for package in ('Pillow','numpy','opencv-python-headless'):
  try:actual[package]=md.version(package)
  except md.PackageNotFoundError:actual[package]='UNAVAILABLE'
 actual['tesseract']=tesseract;expected=config.get('dependencies',{});mismatches={k:{'expected':v,'actual':actual.get(k)} for k,v in expected.items() if actual.get(k)!=v}
 if mismatches:raise SystemExit('FAIL_P0_VISUAL_GOVERNED_DEPENDENCY_MISMATCH='+json.dumps(mismatches,sort_keys=True))
 probe=subprocess.run(['tesseract','--list-langs'],text=True,capture_output=True,check=False);langs=set(probe.stdout.split()) if probe.returncode==0 else set()
 if 'spa' not in langs:raise SystemExit('FAIL_P0_VISUAL_GOVERNED_LANGUAGE_MISSING=spa')
 print('PASS_P0_VISUAL_TEST_DEPENDENCIES=GOVERNED_EXACT '+json.dumps(actual,sort_keys=True))

def run_p0_quality_regressions(repo_root:Path)->None:
 attest_p0_visual_test_dependencies(repo_root);p0=repo_root/'sandbox/story_creator_p0_visual/v1.1'
 commands:list[tuple[str,list[str]]]=[
  ('legacy-negative-suite',[sys.executable,str(p0/'evals/p0_machine_visual_quality_negative_suite.py')]),
  ('human-binding-selftest',[sys.executable,str(p0/'scripts/validate_p0_human_binding.py'),'--self-test']),
  ('legacy-integration-verifier',[sys.executable,str(p0/'scripts/verify_p0_integration_candidate.py')]),
  ('v2-negative-restore-suite',[sys.executable,str(p0/'evals/p0_machine_visual_quality_negative_suite_v2.py')]),
  ('v2-runtime-regressions',[sys.executable,str(p0/'evals/p0_visual_quality_runtime_regression_suite.py')]),
  ('v2-forward-adversarial',[sys.executable,str(p0/'evals/p0_blind_forward_adversarial_test.py')]),
  ('v3-schema-contracts',[sys.executable,str(p0/'scripts/validate_p0_v3_schemas.py')]),
  ('v3-negative-restore-regressions',[sys.executable,str(p0/'evals/p0_visual_fidelity_v3_suite.py')]),
  ('v3-forward-adversarial',[sys.executable,str(p0/'evals/p0_visual_fidelity_forward_adversarial_v3.py')]),
  ('v3-runtime-hash-inventory',[sys.executable,str(p0/'scripts/verify_p0_v3_manifest.py')]),
  ('v3-premerge-compliance',[sys.executable,str(p0/'scripts/audit_p0_handoff_v3_compliance.py'),'--phase','premerge']),
  ('v4-contracts',[sys.executable,str(p0/'scripts/validate_p0_v4_closed_loop.py')]),
  ('v4-graders',[sys.executable,str(p0/'evals/p0_visual_discovery_v4_suite.py')]),
  ('v4-grader-coverage',[sys.executable,str(p0/'evals/p0_visual_grader_coverage_v4.py')]),
  ('v4-closed-loop',[sys.executable,str(p0/'evals/p0_visual_closed_loop_v4_suite.py')]),
  ('v4-durable-state',[sys.executable,str(p0/'evals/p0_visual_durable_state_v4.py')]),
  ('v4-known-failure-regressions',[sys.executable,str(p0/'evals/p0_visual_known_failure_regression_v4.py')]),
  ('v4-forward-adversarial',[sys.executable,str(p0/'evals/p0_visual_forward_adversarial_v4.py')]),
  ('v4-independent-omission-sweep',[sys.executable,str(p0/'evals/p0_independent_omission_sweep_v4.py')]),
  ('v4-reader-producer-contract',[sys.executable,str(p0/'evals/p0_reader_producer_contract_v4.py')]),
  ('v4-grader-producer-field-audit',[sys.executable,str(p0/'evals/p0_grader_producer_field_audit_v4.py')]),
  ('p0-5-blind-annotation-contract',[sys.executable,str(repo_root/'sandbox/lf_contract_gate_test/P0_5_BLIND_ANNOTATION_CONTRACT_V1.py')]),
 ]
 evidence_dir=repo_root/'.audit-output/creating-integral-user-stories/p0-v3';evidence_dir.mkdir(parents=True,exist_ok=True);env=os.environ.copy()
 if env.get('P0_CI_ENGINEERING_REGRESSION') is not None:raise SystemExit('FAIL_P0_CI_ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN')
 for label,command in commands:
  completed=subprocess.run(command,cwd=repo_root,text=True,capture_output=True,check=False,env=env);output=(completed.stdout or '')+(('\nSTDERR:\n'+completed.stderr) if completed.stderr else '');(evidence_dir/f'{label}.log').write_text(output,encoding='utf-8')
  if completed.stdout:print(completed.stdout.rstrip())
  if completed.returncode!=0:
   if completed.stderr:print(completed.stderr.rstrip(),file=sys.stderr)
   raise SystemExit(f"P0_VISUAL_QUALITY_REGRESSION_FAILED[{label}]: {' '.join(command)}")
 snapshot_dir=evidence_dir/'runtime-snapshot';snapshot_dir.mkdir(parents=True,exist_ok=True)
 for rel in ('scripts/p0_visual_fidelity_v3.py','scripts/run_p0_visual_fidelity_v3_private.py','evals/p0-visual-fidelity-runtime-config-v3.json','manifest.visual-fidelity-v3.json'):shutil.copy2(p0/rel,snapshot_dir/Path(rel).name)
 print('PASS_P0_V3_RUNTIME_SNAPSHOT=4_PUBLIC_REPO_FILES');print(f'PASS_P0_VISUAL_QUALITY_REGRESSIONS={len(commands)}/{len(commands)}')

def run_functional_red_team_regression(repo_root:Path)->None:
 command=[sys.executable,str(repo_root/'sandbox/lf_contract_gate_test/functional_red_team_v1_regression.py')];completed=subprocess.run(command,cwd=repo_root,text=True,capture_output=True,check=False)
 if completed.stdout:print(completed.stdout.rstrip())
 if completed.returncode!=0:
  if completed.stderr:print(completed.stderr.rstrip(),file=sys.stderr)
  raise SystemExit('FAIL_FUNCTIONAL_RED_TEAM_V1_REGRESSION')
 parsed=None
 for line in reversed([x.strip() for x in completed.stdout.splitlines() if x.strip()]):
  try:parsed=json.loads(line);break
  except json.JSONDecodeError:pass
 if not isinstance(parsed,dict) or parsed.get('required')!=30 or parsed.get('executed')!=30 or parsed.get('passed')!=30 or parsed.get('all_defended') is not True:raise SystemExit('FAIL_FUNCTIONAL_RED_TEAM_V1_REGRESSION_RESULT')
 print('PASS_FUNCTIONAL_RED_TEAM_V1_REGRESSION=30/30')

def main()->int:
 if os.environ.get('P0_CI_ENGINEERING_REGRESSION') is not None:raise SystemExit('FAIL_P0_CI_ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN')
 exact_blobs=dict(candidate.EXPECTED_RUNTIME_BLOBS);exact_modes={path:'100644' for path in exact_blobs};edge='supabase/functions/run-github-write-perfil-lf/index.ts';alert=candidate.RUNTIME_ALERT_PATH;config=candidate.RUNTIME_PLATFORM_CONFIG_PATH;reconcile=candidate.RUNTIME_RECONCILE_PATH;migration=candidate.RUNTIME_MIGRATION_PATH
 if candidate.evaluate_controlled_runtime_scope(['sandbox/lf_contract_gate_test/example.txt'],branch=candidate.PR_BRANCH,blob_by_path={}) is not False:raise SystemExit('NO_RUNTIME_DELEGATES: expected False')
 print('PASS_NO_RUNTIME_DELEGATES')
 if not candidate.is_allowed_path(candidate.P0_CANDIDATE_PREFIX+'manifest.candidate.json'):raise SystemExit('P0_CANDIDATE_SCOPE: versioned P0 candidate path must be allowed')
 print('PASS_P0_CANDIDATE_SCOPE')
 if candidate.is_allowed_path('sandbox/story_creator_p0_visual/v1.2/manifest.candidate.json'):raise SystemExit('P0_SIBLING_DEFAULT_DENY: unapproved sibling version was allowed')
 print('PASS_P0_SIBLING_DEFAULT_DENY')
 if candidate.is_allowed_path('sandbox/story_creator_p0_visual_evil/v1.1/file.json'):raise SystemExit('P0_PREFIX_BOUNDARY: lookalike P0 prefix was allowed')
 print('PASS_P0_PREFIX_BOUNDARY')
 assert candidate.evaluate_controlled_runtime_scope([edge],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print('PASS_PR_BRANCH_EXACT')
 assert candidate.evaluate_controlled_runtime_scope([config],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print('PASS_PLATFORM_CONFIG_EXACT')
 assert candidate.evaluate_controlled_runtime_scope([reconcile],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True
 repo_root=Path(__file__).resolve().parents[2];reconcile_source=(repo_root/reconcile).read_text(encoding='utf-8');reconcile_workflow=(repo_root/'.github/workflows/lf-github-reconcile-v3.yml').read_text(encoding='utf-8');required_solo_builder_terms=('c.solo_builder_review_policy === true','solo_builder_review_policy: soloBuilderReviewPolicy','required_approving_review_count: 0');combined_reconcile_contract=reconcile_source+'\n'+reconcile_workflow;missing_solo_builder_terms=[term for term in required_solo_builder_terms if term not in combined_reconcile_contract]
 if missing_solo_builder_terms:raise SystemExit(f'RECONCILE_CANONICAL_EXACT: solo-builder contract incomplete: {missing_solo_builder_terms}')
 if 'c.approving_reviews === true' in reconcile_source:raise SystemExit('RECONCILE_CANONICAL_EXACT: legacy human-review gate is still active')
 print('PASS_RECONCILE_CANONICAL_EXACT')
 assert candidate.evaluate_controlled_runtime_scope([edge],branch=candidate.MAIN_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes,main_merge_verified=True) is True;print('PASS_MAIN_VERIFIED')
 expect_error('MAIN_NOT_MERGED','FAIL_RUNTIME_MAIN_NOT_MERGED',[edge],branch=candidate.MAIN_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error('ARBITRARY_BRANCH','FAIL_RUNTIME_BRANCH_MISMATCH',[edge],branch='feature/arbitrary',blobs=exact_blobs,modes=exact_modes);expect_error('MISSING_MIGRATION','FAIL_RUNTIME_MIGRATION_PAIR_MISSING',[alert],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error('EXTRA_EDGE','FAIL_RUNTIME_EDGE_SCOPE',[edge,'supabase/functions/other/index.ts'],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes)
 wrong_blob=dict(exact_blobs);wrong_blob[edge]='0'*40;expect_error('WRONG_BLOB','FAIL_RUNTIME_BLOB_MISMATCH',[edge],branch=candidate.PR_BRANCH,blobs=wrong_blob,modes=exact_modes);wrong_config_blob=dict(exact_blobs);wrong_config_blob[config]='0'*40;expect_error('WRONG_PLATFORM_CONFIG','FAIL_RUNTIME_BLOB_MISMATCH',[config],branch=candidate.PR_BRANCH,blobs=wrong_config_blob,modes=exact_modes);missing_blob=dict(exact_blobs);del missing_blob[edge];expect_error('MISSING_BLOB','FAIL_RUNTIME_BLOB_UNRESOLVED',[edge],branch=candidate.PR_BRANCH,blobs=missing_blob,modes=exact_modes);symlink_modes=dict(exact_modes);symlink_modes[edge]='120000';expect_error('SYMLINK','FAIL_RUNTIME_FILE_MODE',[edge],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=symlink_modes);expect_error('TRAVERSAL','FAIL_RUNTIME_PATH_INVALID',['supabase/functions/../other/index.ts'],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error('UNICODE','FAIL_RUNTIME_PATH_INVALID',['supabase/functions/run-github-write-perfil-lf/índex.ts'],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error('RENAME','FAIL_RUNTIME_EDGE_SCOPE',['supabase/functions/run-github-write-perfil-lf/renamed.ts'],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes)
 assert candidate.evaluate_controlled_runtime_scope([alert,migration],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print('PASS_ALERT_PAIR');print('PASS_PR93_P0_RUNTIME_SCOPE_MATRIX=20/20');run_p0_quality_regressions(repo_root);run_functional_red_team_regression(repo_root);return 0
if __name__=='__main__':raise SystemExit(main())
