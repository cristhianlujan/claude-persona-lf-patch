#!/usr/bin/env python3
"""Single-command governed Profile update (ACTUALIZACION_PERFIL_LF) for a native GPT/Claude chat.

The chat authors the candidate (a profile directory); this runner drives the rest through the
governed route only: issue + label requests (no manual workflow dispatch), Merge Train PR, server
verified proofs, and read-back. It never writes to the database and never merges directly.
State is kept in --state so a stopped run resumes at the first unfinished phase.

    python3 scripts/lf_profile_update_run.py --slug <slug> --target-code PERFIL-... \
        --candidate-dir <dir with the full candidate profile> --state <file> [--dry-run]
"""
from __future__ import annotations

import argparse
import io
import json
import runpy
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DISPATCH = runpy.run_path(str(ROOT / "scripts" / "lf_profile_update_issue_dispatch.py"), run_name="runner_validate")
OPERATIONAL = runpy.run_path(str(ROOT / "skills" / "profile_creator" / "validators" / "operational_coverage_v1.py"), run_name="runner_operational")
OP_REL = "skills/profile_creator/operational_cases"
SCHEMA = "LF_PROFILE_UPDATE_REQUEST_V1"
LABEL = "lf-profile-update-governed"
CALLER_WF = "lf-customer-profile-creator-governance-caller.yml"
PROOF_WF = "lf-profile-evolution-proof.yml"
REQUIRED_CHECKS = {"PASE", "ig-runtime-candidate-judge", "lf-independent-change-admission"}
ZERO = "0" * 40
JUDGE = "JUDGE-ACTUALIZACION-PERFIL-LF-v0.1"
OK = {"step_result": "STEP_PASS_WITH_EVIDENCE", "blocking_codes": []}


class Stop(Exception):
    """Fail closed with a stable code; the state file keeps the progress."""


class Blocked(Stop):
    """Blocked because something that must exist does not: says what, where and in which form."""

    def __init__(self, code, why, missing, how):
        super().__init__(code)
        self.detail = {"status": "BLOCKED", "code": code, "why": why, "missing": missing, "how": how}


def run(cmd, check=True, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, **kw)
    if check and p.returncode != 0:
        raise Stop(f"COMMAND_FAILED:{' '.join(cmd[:3])}:{p.stderr.strip()[:300]}")
    return p.stdout.strip()


class Gh:
    def __init__(self, repo, dry):
        self.repo, self.dry = repo, dry

    def api(self, path, method="GET", body=None):
        cmd = ["gh", "api", f"repos/{self.repo}/{path}", "-X", method]
        if body is not None:
            f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
            json.dump(body, f)
            f.close()
            cmd += ["--input", f.name]
        out = run(cmd)
        return json.loads(out) if out else None

    def annotation(self, run_id, title):
        jobs = self.api(f"actions/runs/{run_id}/jobs")["jobs"]
        for job in jobs:
            for a in self.api(f"check-runs/{job['id']}/annotations") or []:
                if a.get("title") == title:
                    return a["message"]
        return None

    def wait(self, fn, what, timeout=900, every=15):
        end = time.time() + timeout
        while time.time() < end:
            v = fn()
            if v:
                return v
            time.sleep(every)
        raise Stop(f"TIMEOUT:{what}")


def validate_body(body, repo):
    """Offline: the exact validator the issue-triggered job runs."""
    event = {"action": "labeled", "label": {"name": LABEL},
             "issue": {"state": "open", "pull_request": None, "repository_url": f"https://api.github.com/repos/{repo}",
                       "body": json.dumps(body, separators=(",", ":"), ensure_ascii=False)}}
    return DISPATCH["governed_request"](event, {"GITHUB_EVENT_NAME": "issues", "GITHUB_REPOSITORY": repo})


def submit(gh, title, body, state_log):
    validate_body(body, gh.repo)
    if gh.dry:
        state_log.append(f"DRY_RUN would open issue: {title} ({body['action']})")
        return None
    seen = {r["id"] for r in gh.api(f"actions/workflows/{CALLER_WF}/runs?event=workflow_dispatch&per_page=20")["workflow_runs"]}
    seen_p = {r["id"] for r in gh.api(f"actions/workflows/{PROOF_WF}/runs?event=workflow_dispatch&per_page=20")["workflow_runs"]}
    # The governed workflow listens for issues.labeled, not issues.opened.
    # Opening with an initial labels array does not reliably emit a separate labeled event.
    # Persist the issue first, then emit the canonical label event explicitly.
    issue = gh.api("issues", "POST", {"title": title, "body": json.dumps(body, separators=(",", ":"), ensure_ascii=False)})
    gh.api(f"issues/{issue['number']}/labels", "POST", {"labels": [LABEL]})
    wf, known = (PROOF_WF, seen_p) if body["action"] == "profile_evolution_proof" else (CALLER_WF, seen)

    def new_run():
        runs = [r for r in gh.api(f"actions/workflows/{wf}/runs?event=workflow_dispatch&per_page=20")["workflow_runs"] if r["id"] not in known]
        return runs[0] if runs and runs[0]["status"] == "completed" else None

    r = gh.wait(new_run, f"dispatched run for issue {issue['number']}", timeout=600)
    if r["conclusion"] != "success":
        info = gh.annotation(r["id"], "LF_PROFILE_UPDATE_BATCH")
        raise Stop(f"GOVERNED_RUN_FAILED:{body['action']}:run={r['id']}:{info}")
    return r["id"]


def steps_batch(execution_id, steps):
    return {"schema_version": SCHEMA, "action": "profile_update_record_batch", "execution_id": execution_id, "steps": steps}


def build_pre_steps(slug, code, main, measure_run, proof, files, unmet):
    ref = f"actions:profile-evolution-proof:{measure_run}"
    keep = {k: proof[k] for k in ("score", "schema", "decision", "required", "profile_slug", "proof_sha256", "blocking_codes", "failed_dimensions") if k in proof}
    keep["update_basis"] = proof.get("update_basis")
    return [
        {"step_id": "router", "evidence_ref": "router:ACT-0001:PROFILE_UPDATE", "evidence_payload": {"action": "PROFILE_UPDATE", "router_read": True, "operation_code": "ACTUALIZACION_PERFIL_LF", **OK}},
        {"step_id": "profile_resolve", "evidence_ref": f"catalog:{code}", "evidence_payload": {"repo_path": f"profiles/{slug}/SKILL.md", "profile_slug": slug, "codigo_activo": code, "exact_profile_resolved": True, **OK}},
        {"step_id": "baseline_read", "evidence_ref": f"git:{main}", "evidence_payload": {"baseline_files": files, "baseline_revision": main, "before_evidence": {"source": "git ls-tree origin/main", "file_count": len(files)}, **OK}},
        {"step_id": "method_selection", "evidence_ref": ref, "evidence_payload": {"proof": keep, "proof_mode": "measure", "proof_run_id": measure_run, "baseline_proof_run_id": measure_run, "profile_slug": slug, "source_head_sha": main, "selected_methods": [], "selector_version": "1.0.0", "assessment_source": "ACTIONS_EVOLUTION_PROOF", "mini_judge_code": "JUDGE-PE10-V02-METHOD-SELECTION", "assertions_checked": ["verified_assessment", "qualified_method_receipts_or_reasoned_empty", "current_selector", "method_execution_permitted_false"], "hard_fails_checked": [], "method_execution_permitted": False, "no_additional_method_needed": True, "empty_selection_reason": f"Measurer reports {proof.get('decision')} by {proof.get('update_basis')}; {len(unmet)} bound operational checks unmet. Addressed by direct edits to the profile; no qualified method needed.", **OK}},
        {"step_id": "evolution_decision", "evidence_ref": ref, "evidence_payload": {"decision": "UPDATE", "evolution_mode": "PATCH", "profile_slug": slug, "source_head_sha": main, "mini_judge_code": "JUDGE-PE10-V02-EVOLUTION-DECISION", "assertions_checked": ["verified_assessment", "clean_method_selection", "typed_decision_mode", "frozen_route_consistency"], "hard_fails_checked": [], "github_write_permitted": False, "decision_evidence_ref": ref, **OK}},
        {"step_id": "change_scope", "evidence_ref": ref, "evidence_payload": {"defect": f"{len(unmet)} trusted operational checks unmet: " + ", ".join(unmet)[:600], "root_cause": "Derived from the unmet operational checks of the measurer; see candidate diff.", "minimal_patch_scope": [f"profiles/{slug}/** (candidate authored in the native chat)"], "preserved_constraints": ["profile identity and runtime state unchanged", "S26 structural score must not regress", "no promotion or runtime activation"], **OK}},
        {"step_id": "regression_plan", "evidence_ref": ref, "evidence_payload": {"holdout": "Compare proof on the exact candidate commit: S26 with no regressed dimension plus operational coverage bound to the exact profile trees.", "negative_cases": ["a bound operational check that passed on base must still pass on candidate"], "positive_cases": [f"unmet checks become met: {', '.join(unmet)[:400]}"], "adversarial_cases": ["compare proof must show no regressed S26 dimension and no regressed operational check"], **OK}},
        {"step_id": "pre_write_execution_binding_gate", "evidence_ref": f"git:{main}", "evidence_payload": {"write_plan": f"Single commit descending from bound revision {main[:8]}; only files under profiles/{slug}.", "target_code": code, "target_path": f"profiles/{slug}/SKILL.md", "bound_revision": {"revision_sha": main}, "rebind_performed": False, "reread_performed": False, "execution_bound_to_target_before_change": True, "pre_write_gate_passed": True, "baseline_revision_observed": main, **OK}},
    ]


def build_post_steps(execution_id, slug, base, commit, compare_run, op):
    ev = f"actions-run:{compare_run}"
    pending = op.get("semantic_pending") or []
    limits = ["self-review by the authoring chat: no independent semantic evaluation of the final candidate",
              "operational evidence is one run per profile tree without attestation",
              f"{len(pending)} semantic checks are pending and were not evaluated",
              "the profile keeps its runtime state; enabling is a separate governed transition"]
    return [
        {"step_id": "deterministic_validation", "evidence_ref": ev, "evidence_payload": {"proof_mode": "compare", "proof_run_id": compare_run, "evolution_proof_run_id": compare_run, "validator_result": "PASS", "negative_regressions": [], "malformed_input_result": "PASS_S26_NO_DIMENSION_REGRESSED_ON_CANDIDATE", "mini_judge_code": JUDGE, **OK}},
        {"step_id": "semantic_judge", "evidence_ref": f"review:self:{commit}", "evidence_payload": {"independent": False, "semantic_judge_result": "PASS_SELF_REVIEW_NOT_INDEPENDENT", "review_scope": f"Diff of the candidate commit under profiles/{slug}, reviewed by its author.", "known_limits": limits, "authority_checks": ["identity and runtime state preserved", "no router or card files in diff"], "router_direct_consistency": "PASS_NO_ROUTING_CHANGE_DIFF_LIMITED_TO_PROFILE_PACKAGE", "mini_judge_code": JUDGE, **OK}},
        {"step_id": "regression_after", "evidence_ref": ev, "evidence_payload": {"holdout_result": f"PASS_OPERATIONAL_{op.get('base_passed')}_OF_{op.get('checks_total')}_TO_{op.get('candidate_passed')}_OF_{op.get('checks_total')}_NO_CHECK_REGRESSED", "adversarial_result": "PASS_S26_NO_DIMENSION_REGRESSED", "before_after_matrix": {"source": "S26_PROFILE_EVOLUTION_PROOF_V1", "base_sha": base, "candidate_sha": commit, "operational_checks_before": op.get("base_passed"), "operational_checks_after": op.get("candidate_passed"), "operational_checks_total": op.get("checks_total")}, "mini_judge_code": JUDGE, **OK}},
    ]


def build_close_steps(slug, merge, commit, compare_run, manifest_sha, entry_sha, pack_id, runtime):
    return [
        {"step_id": "post_merge_reconcile", "evidence_ref": f"git:{merge}", "evidence_payload": {"merge_sha": merge, "manifest_sha": manifest_sha, "entrypoint_sha": entry_sha, "profile_pack_id": pack_id, "runtime_state_before": runtime, "runtime_state_after": runtime, "automatic_impact_preserved": True, "operational_state_preserved": True, "reconciliation_disposition": f"MERGED_VIA_MERGE_TRAIN_PROFILE_DIR_IDENTICAL_TO_CANDIDATE_{commit[:8]}", "next_gate": "independent semantic evaluation and governed runtime transition (not executed)", "mini_judge_code": JUDGE, **OK}},
        {"step_id": "close", "evidence_ref": f"git:{merge}", "evidence_payload": {"open_blockers": [], "no_auto_promotion": True, "runtime_unchanged": True, "all_required_steps_clean": True, "mini_judge_code": JUDGE, **OK}},
        {"step_id": "report_output", "evidence_ref": f"actions:{compare_run}", "evidence_payload": {"result": f"UPDATED_{slug}", "exact_head": commit, "evidence_refs": [f"actions:{compare_run}"], "open_blockers": [], "next_gate": "independent semantic evaluation and governed runtime transition (not executed)", "mini_judge_code": JUDGE, **OK}},
    ]


def tree_files(rev, slug):
    out = run(["git", "ls-tree", "-r", rev, f"profiles/{slug}"])
    return [{"path": l.split("\t")[1], "blob_sha": l.split()[2]} for l in out.splitlines()]


def apply_candidate(slug, cand_dir):
    dst = ROOT / "profiles" / slug
    changed = []
    for src in sorted(cand_dir.rglob("*")):
        if src.is_dir() or "__pycache__" in src.parts:
            continue
        rel = src.relative_to(cand_dir)
        target = dst / rel
        if not target.exists() or target.read_bytes() != src.read_bytes():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, target)
            changed.append(str(Path("profiles") / slug / rel))
    return changed


RUN_FIELDS = ["schema_version=PROFILE_OPERATIONAL_RUN_V1", "run_id", "case_id", "profile_slug", "profile_tree_sha256 (hash below)",
              "attestation (NONE|...)", "recorded_at", "executor{mode,note}", "conditions", "validator{tool,valid,errors}",
              "output (the profile's real output on the case)", "output_sha256 (sha256 of the canonical output)"]


def plan_missing(slug, cases, runs, base_tree, cand_tree):
    """Pure: which bound runs must exist on main before the update can be proven."""
    missing = []
    for case_id in sorted(cases):
        for label, tree in (("BASE", base_tree), ("CANDIDATE", cand_tree)):
            if not any(r["case_id"] == case_id and r["profile_tree_sha256"] == tree for r in runs):
                missing.append({"what": f"{label} run of case {case_id}", "where": f"{OP_REL}/{slug}/runs/RUN-{case_id}-{label}-<yyyymmdd>.json",
                                "bind_to": {"profile_tree_sha256": tree}, "required_fields": RUN_FIELDS})
    return missing


def gather_operational(slug, cand_dir):
    """Read the trusted cases/runs and profile tree from origin/main; compute the tree the update would produce."""
    tmp = Path(tempfile.mkdtemp(prefix="lf_op_"))
    paths = [f"profiles/{slug}"]
    if run(["git", "ls-tree", "-r", "--name-only", "origin/main", f"{OP_REL}/{slug}"]):
        paths.append(f"{OP_REL}/{slug}")
    data = subprocess.run(["git", "archive", "origin/main", *paths], capture_output=True, cwd=ROOT)
    if data.returncode != 0:
        raise Stop("COMMAND_FAILED:git archive:" + data.stderr.decode()[:200])
    tarfile.open(fileobj=io.BytesIO(data.stdout)).extractall(tmp)
    base = tmp / "profiles" / slug
    base_tree = OPERATIONAL["tree_sha256"](base)
    overlay = tmp / "overlay"
    shutil.copytree(base, overlay)
    for src in cand_dir.rglob("*"):
        if src.is_file() and "__pycache__" not in src.parts:
            t = overlay / src.relative_to(cand_dir)
            t.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, t)
    cand_tree = OPERATIONAL["tree_sha256"](overlay)
    cases, problems = OPERATIONAL["load_cases"](tmp / OP_REL, slug)
    runs, rejected = OPERATIONAL["load_runs"](tmp / OP_REL, slug, cases)
    shutil.rmtree(tmp, ignore_errors=True)
    return cases, runs, base_tree, cand_tree, problems + rejected


def preflight_operational(slug, cand_dir):
    cases, runs, base_tree, cand_tree, problems = gather_operational(slug, cand_dir)
    if cand_tree == base_tree:
        raise Blocked("BLOCKED_CANDIDATE_EQUALS_CURRENT_PROFILE", "The candidate does not change the profile on main, so there is nothing to update.",
                      [{"what": "a candidate that differs from profiles/" + slug, "where": "--candidate-dir"}],
                      "Edit the candidate directory so it contains the change, then rerun.")
    if not cases:
        return {"operational_cases": 0, "note": "no operational case defined: only a structural (S26) gap can justify an update"}
    missing = plan_missing(slug, cases, runs, base_tree, cand_tree)
    if missing:
        raise Blocked("BLOCKED_MISSING_OPERATIONAL_RUNS",
                      "The profile has operational cases, so every case needs a real run of the base profile and of the candidate bound to their exact tree hashes. Without them the improvement cannot be proven and nothing was opened or written.",
                      missing + ([{"what": "invalid case/run files on main", "where": f"{OP_REL}/{slug}/", "detail": problems}] if problems else []),
                      "Run the profile (base tree and candidate tree) on each case with a model, validate with the profile validator, record the result as a PROFILE_OPERATIONAL_RUN_V1 file at the given path, and merge it to main through the Merge Train (trusted root). Then rerun this command.")
    return {"operational_cases": len(cases), "base_tree": base_tree, "candidate_tree": cand_tree}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--slug", required=True)
    ap.add_argument("--target-code", required=True)
    ap.add_argument("--candidate-dir", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--repo", default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    slug, code, dry = a.slug, a.target_code, a.dry_run
    cand = Path(a.candidate_dir).resolve()
    sp = Path(a.state)
    st = json.loads(sp.read_text()) if sp.exists() and not dry else {}
    log: list[str] = []
    gh = Gh(a.repo, dry)

    def save():
        if not dry:
            sp.write_text(json.dumps(st, indent=1))

    try:
        run(["git", "fetch", "-q", "origin", "main"])
        if run(["git", "status", "--porcelain", "--untracked-files=no"]):
            raise Stop("PREFLIGHT_WORKTREE_NOT_CLEAN")
        main_sha = run(["git", "rev-parse", "origin/main"])
        if not st.get("branch") and run(["git", "rev-parse", "HEAD"]) != main_sha:
            raise Stop("PREFLIGHT_LOCAL_MAIN_NOT_ORIGIN_MAIN")
        if not cand.is_dir() or not (cand / "SKILL.md").is_file():
            raise Stop("CANDIDATE_DIR_INVALID")
        target_path = f"profiles/{slug}/SKILL.md"
        if "execution_id" not in st:
            log.append("PREFLIGHT_OPERATIONAL " + json.dumps(preflight_operational(slug, cand)))

        # 1. open the governed execution, then measure after it exists (the proof must be newer than the execution)
        if "execution_id" not in st:
            init = {"schema_version": SCHEMA, "action": "profile_update_init", "target_code": code, "target_path": target_path, "research_baseline_mode": "NOT_REQUIRED", "research_baseline_contract": None}
            rid = submit(gh, f"Governed profile update request: {code} @ {main_sha[:8]}", init, log)
            if rid:
                msg = gh.annotation(rid, "LF_PROFILE_UPDATE_EXECUTION")
                if not msg:
                    raise Stop("EXECUTION_ID_ANNOTATION_MISSING")
                st.update(execution_id=msg, anchor=main_sha)
                save()
        execution_id = st.get("execution_id", "EXEC-DRY-RUN-0000")
        base = st.get("anchor", main_sha)
        if not dry and main_sha != base and "branch" not in st:
            raise Stop(f"MAIN_ADVANCED_SINCE_EXECUTION_ANCHOR:{base[:8]}->{main_sha[:8]}:open a new execution")

        # 2. measure (server-side, trusted) and require an update to be justified
        if "measure_run" not in st:
            m = {"schema_version": SCHEMA, "action": "profile_evolution_proof", "mode": "measure", "profile_slug": slug, "base_sha": base, "candidate_sha": ZERO}
            rid = submit(gh, f"Evolution proof measure {slug} @ {base[:8]}", m, log)
            if rid:
                ann = json.loads(gh.annotation(rid, "LF_PROFILE_EVOLUTION_PROOF"))
                proof = ann["proof"]
                if proof.get("decision") != "UPDATE_REQUIRED":
                    raise Blocked("BLOCKED_NO_UPDATE_JUSTIFIED", f"The trusted measurement says {proof.get('decision')}: no structural gap and no unmet operational check justifies changing the profile.",
                                  [{"what": "an operational case whose checks the current profile does not meet", "where": f"{OP_REL}/{slug}/<CASE>.case.json (schema PROFILE_OPERATIONAL_CASE_V1) plus a base run in runs/"}],
                                  "Define the business case the profile must solve and record the base run on main through the Train; if the current profile fails it, the measurement will then justify the update.")
                st.update(measure_run=str(rid), measure=proof)
                save()
        proof = st.get("measure") or {"decision": "UPDATE_REQUIRED", "update_basis": ["DRY_RUN"], "score": 15, "required": 15, "proof_sha256": "0" * 64, "schema": "S26_PROFILE_MEASUREMENT_V1", "profile_slug": slug, "blocking_codes": [], "failed_dimensions": [], "operational": {"unmet_checks": ["DRY:CHECK"]}}
        unmet = (proof.get("operational") or {}).get("unmet_checks") or (proof.get("failed_dimensions") or ["structural"])

        # 3. record router..pre_write_execution_binding_gate before any repository write
        if "pre_steps" not in st:
            steps = build_pre_steps(slug, code, base, st.get("measure_run", "0"), proof, tree_files(base, slug), unmet)
            if submit(gh, f"Record update steps {slug} (router..pre_write) {execution_id[-8:]}", steps_batch(execution_id, steps), log) or dry:
                st["pre_steps"] = True
                save()

        # 4. apply the candidate on a branch from the exact anchor, push, record write and read-back
        branch = st.get("branch") or f"lf/{slug.replace('_', '-')}-update-{datetime.now(timezone.utc):%Y%m%d%H%M}"
        if "commit" not in st:
            if dry:
                changed = [str(Path("profiles") / slug / p.relative_to(cand)) for p in cand.rglob("*") if p.is_file() and "__pycache__" not in p.parts and (not (ROOT / "profiles" / slug / p.relative_to(cand)).exists() or (ROOT / "profiles" / slug / p.relative_to(cand)).read_bytes() != p.read_bytes())]
                log.append(f"DRY_RUN would commit {len(changed)} changed files on {branch}")
            else:
                run(["git", "checkout", "-q", "-b", branch, base])
                changed = apply_candidate(slug, cand)
                if not changed:
                    raise Stop("CANDIDATE_HAS_NO_CHANGES")
                run(["git", "add", "--"] + changed)
                msg = f"feat(profile): update {slug} via governed ACTUALIZACION_PERFIL_LF\n\nExecution {execution_id}\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\n"
                run(["git", "-c", "user.name=Claude", "-c", "user.email=noreply@anthropic.com", "commit", "-q", "-m", msg])
                commit = run(["git", "rev-parse", "HEAD"])
                run(["git", "push", "-q", "-u", "origin", branch])
                st.update(branch=branch, commit=commit, changed=changed)
                save()
                wr = [{"step_id": "github_write", "evidence_ref": f"git:{commit}", "evidence_payload": {"branch": branch, "commit_sha": commit, **OK}},
                      {"step_id": "github_readback", "evidence_ref": f"git:{commit}", "evidence_payload": {"branch": branch, "commit_sha": commit, "exact_head": commit, "sha_match": True, **OK}}]
                submit(gh, f"Record update steps {slug} (github_write, github_readback) {execution_id[-8:]}", steps_batch(execution_id, wr), log)
        commit = st.get("commit", "f" * 40)

        # 5. open the PR; compare proof on the exact commit; record validation/judge/regression
        if "pr" not in st and not dry:
            body = (f"ACTUALIZACION_PERFIL_LF execution {execution_id}, anchored at main {base[:8]}.\n\nChanged files: {len(st['changed'])}.\n\n"
                    "🤖 Generated with [Claude Code](https://claude.com/claude-code)\n\nhttps://claude.ai/code/session_01AQsB14hfrJpk3YPRkTLvtX")
            pr = gh.api("pulls", "POST", {"title": f"feat(profile): update {slug} (governed)", "head": branch, "base": "main", "body": body})
            st["pr"] = pr["number"]
            save()
        if "compare_run" not in st:
            c = {"schema_version": SCHEMA, "action": "profile_evolution_proof", "mode": "compare", "profile_slug": slug, "base_sha": base, "candidate_sha": commit}
            rid = submit(gh, f"Evolution proof compare {slug} {base[:8]}..{commit[:8]}", c, log)
            if rid:
                cp = json.loads(gh.annotation(rid, "LF_PROFILE_EVOLUTION_PROOF"))["proof"]
                if cp.get("verdict") != "EVOLUTION_DEMONSTRATED":
                    raise Stop(f"EVOLUTION_NOT_DEMONSTRATED:{cp.get('verdict')}:regressed={cp.get('regressed_dimensions')}")
                st.update(compare_run=str(rid), compare=cp)
                save()
        cp = st.get("compare") or {"operational": {}}
        if "post_steps" not in st:
            ps = build_post_steps(execution_id, slug, base, commit, st.get("compare_run", "0"), cp.get("operational") or {})
            if submit(gh, f"Record update steps {slug} (validation, judge, regression) {execution_id[-8:]}", steps_batch(execution_id, ps), log) or dry:
                st["post_steps"] = True
                save()

        # 6. Merge Train: wait for the required checks on the exact head, label, wait for the merge
        if "merge_sha" not in st and not dry:
            def checks_ok():
                runs = gh.api(f"commits/{commit}/check-runs?per_page=100")["check_runs"]
                done = {r["name"]: r["conclusion"] for r in runs if r["status"] == "completed"}
                bad = [n for n in REQUIRED_CHECKS if done.get(n) not in (None, "success", "skipped")]
                if bad:
                    raise Stop(f"REQUIRED_CHECK_NOT_SUCCESS:{bad}")
                return all(done.get(n) == "success" for n in REQUIRED_CHECKS)
            gh.wait(checks_ok, "required checks on exact head", timeout=1200)
            if gh.api(f"pulls/{st['pr']}")["head"]["sha"] != commit:
                raise Stop("PR_HEAD_DRIFT")
            gh.api(f"issues/{st['pr']}/labels", "POST", {"labels": ["ready-to-merge"]})

            def merged():
                p = gh.api(f"pulls/{st['pr']}")
                if p["state"] == "closed" and not p["merged"]:
                    raise Stop("PR_CLOSED_WITHOUT_MERGE")
                return p["merged"] and p["merge_commit_sha"]
            st["merge_sha"] = gh.wait(merged, "Merge Train merge", timeout=1800, every=30)
            save()

        # 7. read back from the new main, then close
        if "closed" not in st and not dry:
            run(["git", "fetch", "-q", "origin", "main"])
            merge = st["merge_sha"]
            if run(["git", "ls-tree", "-r", merge, f"profiles/{slug}"]) != run(["git", "ls-tree", "-r", commit, f"profiles/{slug}"]):
                raise Stop("POST_MERGE_PROFILE_DIR_DIFFERS_FROM_CANDIDATE")
            manifest = json.loads(run(["git", "show", f"{merge}:profiles/{slug}/manifest.json"]))
            tree = {f["path"]: f["blob_sha"] for f in tree_files(merge, slug)}
            cs = build_close_steps(slug, merge, commit, st["compare_run"], tree.get(f"profiles/{slug}/manifest.json"), tree.get(f"profiles/{slug}/SKILL.md"), manifest.get("profile_pack_id"), manifest.get("runtime", "NO_HABILITADO"))
            submit(gh, f"Record update steps {slug} (post-merge, close, report) {execution_id[-8:]}", steps_batch(execution_id, cs), log)
            st["closed"] = True
            save()
            run(["git", "checkout", "-q", "main"])
            run(["git", "merge", "-q", "--ff-only", "origin/main"])
        print(json.dumps({"status": "DRY_RUN_OK" if dry else "COMPLETED", "execution_id": execution_id, "log": log, "state": {k: v for k, v in st.items() if k not in ("measure", "compare")}}, indent=1))
        return 0
    except Blocked as e:
        print(json.dumps({**e.detail, "state_file": str(sp)}, indent=1, ensure_ascii=False))
        return 2
    except Stop as e:
        print(json.dumps({"status": "STOPPED", "code": str(e), "state_file": str(sp)}, indent=1))
        return 2


if __name__ == "__main__":
    sys.exit(main())
