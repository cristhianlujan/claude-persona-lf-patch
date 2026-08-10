#!/usr/bin/env python3
"""Regression matrix for the pinned PR93 runtime source gate plus P0 quality gate."""
from __future__ import annotations
import os,shutil,subprocess,sys
from pathlib import Path
import PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT as candidate
sys.dont_write_bytecode=True
def expect_error(name:str,code:str,changed:list[str],*,branch:str,blobs:dict[str,str],modes:dict[str,str]|None=None,main_merge_verified:bool=False)->None:
    try:candidate.evaluate_controlled_runtime_scope(changed,branch=branch,blob_by_path=blobs,mode_by_path=modes,main_merge_verified=main_merge_verified)
    except candidate.RuntimeScopeError as exc:
        if exc.code!=code:raise SystemExit(f"{name}: expected {code}, got {exc.code}: {exc}")
        print(f"PASS_{name}={code}");return
    raise SystemExit(f"{name}: expected {code}, but scope was accepted")
def ensure_p0_visual_test_dependencies(repo_root:Path)->None:
    if os.environ.get("CI")!="true":return
    requirements=repo_root/"sandbox/story_creator_p0_visual/v1.1/requirements-p0-visual-quality.txt";subprocess.run([sys.executable,"-m","pip","install","--disable-pip-version-check","-r",str(requirements)],check=True)
    if shutil.which("tesseract") is None:
        subprocess.run(["sudo","apt-get","update","-qq"],check=True);subprocess.run(["sudo","apt-get","install","-y","-qq","tesseract-ocr","tesseract-ocr-spa"],check=True)
    probe=subprocess.run(["tesseract","--list-langs"],text=True,capture_output=True,check=False);langs=set(probe.stdout.split()) if probe.returncode==0 else set()
    if "spa" not in langs:subprocess.run(["sudo","apt-get","update","-qq"],check=True);subprocess.run(["sudo","apt-get","install","-y","-qq","tesseract-ocr-spa"],check=True)
    os.environ["P0_CI_ENGINEERING_REGRESSION"]="1";print("PASS_P0_VISUAL_TEST_DEPENDENCIES=PINNED_PYTHON_PLUS_TESSERACT_SPA")
def run_p0_quality_regressions(repo_root:Path)->None:
    ensure_p0_visual_test_dependencies(repo_root);commands=[[sys.executable,str(repo_root/"sandbox/story_creator_p0_visual/v1.1/evals/p0_machine_visual_quality_negative_suite.py")],[sys.executable,str(repo_root/"sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_human_binding.py"),"--self-test"],[sys.executable,str(repo_root/"sandbox/story_creator_p0_visual/v1.1/scripts/verify_p0_integration_candidate.py")]]
    for command in commands:
        completed=subprocess.run(command,cwd=repo_root,text=True,capture_output=True,check=False,env=os.environ.copy())
        if completed.stdout:print(completed.stdout.rstrip())
        if completed.returncode!=0:
            if completed.stderr:print(completed.stderr.rstrip(),file=sys.stderr)
            raise SystemExit(f"P0_VISUAL_QUALITY_REGRESSION_FAILED: {' '.join(command)}")
    print("PASS_P0_VISUAL_QUALITY_REGRESSIONS=3/3")
def main()->int:
    exact_blobs=dict(candidate.EXPECTED_RUNTIME_BLOBS);exact_modes={path:"100644" for path in exact_blobs};edge="supabase/functions/run-github-write-perfil-lf/index.ts";alert=candidate.RUNTIME_ALERT_PATH;config=candidate.RUNTIME_PLATFORM_CONFIG_PATH;reconcile=candidate.RUNTIME_RECONCILE_PATH;migration=candidate.RUNTIME_MIGRATION_PATH
    if candidate.evaluate_controlled_runtime_scope(["sandbox/lf_contract_gate_test/example.txt"],branch=candidate.PR_BRANCH,blob_by_path={}) is not False:raise SystemExit("NO_RUNTIME_DELEGATES: expected False")
    print("PASS_NO_RUNTIME_DELEGATES")
    if not candidate.is_allowed_path(candidate.P0_CANDIDATE_PREFIX+"manifest.candidate.json"):raise SystemExit("P0_CANDIDATE_SCOPE: versioned P0 candidate path must be allowed")
    print("PASS_P0_CANDIDATE_SCOPE")
    if candidate.is_allowed_path("sandbox/story_creator_p0_visual/v1.2/manifest.candidate.json"):raise SystemExit("P0_SIBLING_DEFAULT_DENY: unapproved sibling version was allowed")
    print("PASS_P0_SIBLING_DEFAULT_DENY")
    if candidate.is_allowed_path("sandbox/story_creator_p0_visual_evil/v1.1/file.json"):raise SystemExit("P0_PREFIX_BOUNDARY: lookalike P0 prefix was allowed")
    print("PASS_P0_PREFIX_BOUNDARY")
    assert candidate.evaluate_controlled_runtime_scope([edge],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print("PASS_PR_BRANCH_EXACT");assert candidate.evaluate_controlled_runtime_scope([config],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print("PASS_PLATFORM_CONFIG_EXACT");assert candidate.evaluate_controlled_runtime_scope([reconcile],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True
    repo_root=Path(__file__).resolve().parents[2];reconcile_source=(repo_root/reconcile).read_text(encoding="utf-8");reconcile_workflow=(repo_root/".github/workflows/lf-github-reconcile-v3.yml").read_text(encoding="utf-8");required_solo_builder_terms=("c.solo_builder_review_policy === true","solo_builder_review_policy: soloBuilderReviewPolicy","required_approving_review_count: 0");combined_reconcile_contract=reconcile_source+"\n"+reconcile_workflow;missing_solo_builder_terms=[term for term in required_solo_builder_terms if term not in combined_reconcile_contract]
    if missing_solo_builder_terms:raise SystemExit(f"RECONCILE_CANONICAL_EXACT: solo-builder contract incomplete: {missing_solo_builder_terms}")
    if "c.approving_reviews === true" in reconcile_source:raise SystemExit("RECONCILE_CANONICAL_EXACT: legacy human-review gate is still active")
    print("PASS_RECONCILE_CANONICAL_EXACT");assert candidate.evaluate_controlled_runtime_scope([edge],branch=candidate.MAIN_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes,main_merge_verified=True) is True;print("PASS_MAIN_VERIFIED")
    expect_error("MAIN_NOT_MERGED","FAIL_RUNTIME_MAIN_NOT_MERGED",[edge],branch=candidate.MAIN_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error("ARBITRARY_BRANCH","FAIL_RUNTIME_BRANCH_MISMATCH",[edge],branch="feature/arbitrary",blobs=exact_blobs,modes=exact_modes);expect_error("MISSING_MIGRATION","FAIL_RUNTIME_MIGRATION_PAIR_MISSING",[alert],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error("EXTRA_EDGE","FAIL_RUNTIME_EDGE_SCOPE",[edge,"supabase/functions/other/index.ts"],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes)
    wrong_blob=dict(exact_blobs);wrong_blob[edge]="0"*40;expect_error("WRONG_BLOB","FAIL_RUNTIME_BLOB_MISMATCH",[edge],branch=candidate.PR_BRANCH,blobs=wrong_blob,modes=exact_modes);wrong_config_blob=dict(exact_blobs);wrong_config_blob[config]="0"*40;expect_error("WRONG_PLATFORM_CONFIG","FAIL_RUNTIME_BLOB_MISMATCH",[config],branch=candidate.PR_BRANCH,blobs=wrong_config_blob,modes=exact_modes);missing_blob=dict(exact_blobs);del missing_blob[edge];expect_error("MISSING_BLOB","FAIL_RUNTIME_BLOB_UNRESOLVED",[edge],branch=candidate.PR_BRANCH,blobs=missing_blob,modes=exact_modes);symlink_modes=dict(exact_modes);symlink_modes[edge]="120000";expect_error("SYMLINK","FAIL_RUNTIME_FILE_MODE",[edge],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=symlink_modes);expect_error("TRAVERSAL","FAIL_RUNTIME_PATH_INVALID",["supabase/functions/../other/index.ts"],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error("UNICODE","FAIL_RUNTIME_PATH_INVALID",["supabase/functions/run-github-write-perfil-lf/índex.ts"],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);expect_error("RENAME","FAIL_RUNTIME_EDGE_SCOPE",["supabase/functions/run-github-write-perfil-lf/renamed.ts"],branch=candidate.PR_BRANCH,blobs=exact_blobs,modes=exact_modes);assert candidate.evaluate_controlled_runtime_scope([alert,migration],branch=candidate.PR_BRANCH,blob_by_path=exact_blobs,mode_by_path=exact_modes) is True;print("PASS_ALERT_PAIR");print("PASS_PR93_P0_RUNTIME_SCOPE_MATRIX=20/20");run_p0_quality_regressions(repo_root);return 0
if __name__=="__main__":raise SystemExit(main())
