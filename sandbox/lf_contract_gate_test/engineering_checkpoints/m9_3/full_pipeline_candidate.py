#!/usr/bin/env python3
"""M9.3 FULL_PIPELINE_CANDIDATE.

Fail-closed verifier for a LIVE read-only comparison of the full vNext
Core -> Semantics -> Curator -> Validator pipeline versus 5.13, across
the governed M9.4 cohorts through T-EQUIV.

The input MUST be evidence captured from actual external runtime execution,
not a fabricated local fixture. This script validates the received evidence;
it does not launch the pipeline or certify that a live run occurred by itself.
It cannot PASS without the comparison traces and authoritative DB readback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_CODE = "ENG_M9_3_FULL_PIPELINE_CANDIDATE"
PROJECT = "mhwmirqcgxxukpctffuv"
ASSETS = {
    "EDGE_FN_INPUT_GOVERNANCE_AGENT_V1",
    "EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1",
    "EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1",
}
COHORTS = {"AUTH", "FORMS", "NAVIGATION", "DESIGN", "ONBOARDING", "RECOVERY", "API"}
STAGES = ("CORE", "SEMANTICS", "CURATOR", "VALIDATOR")
HEX64 = re.compile(r"^[a-f0-9]{64}$")
HEX40 = re.compile(r"^[a-f0-9]{40}$")


def sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def valid_ref(s: object) -> bool:
    return isinstance(s, str) and bool(re.match(r"^(supabase|github|sentinelx)://[^ ]{12,}$", s))


def admissible_t_equiv(eq: dict) -> bool:
    """A D4 hold proves observation, never semantic equivalence or promotion."""
    diff = eq.get("difference_count")
    d0 = (eq.get("status") == "PASS" and eq.get("result") == "PASS_EQUIVALENT"
          and diff == 0 and eq.get("semantic_hold") is not True)
    d4 = (eq.get("status") == "CLASSIFIED_HOLD"
          and eq.get("result") == "BLOCKED_DIVERGENCE"
          and eq.get("comparison_level") == "D4"
          and type(diff) is int and diff > 0
          and eq.get("semantic_hold") is True
          and eq.get("promotion_authorized") is False)
    return d0 or d4


def self_test() -> int:
    positive = {"status":"PASS","result":"PASS_EQUIVALENT","difference_count":0}
    hold = {"status":"CLASSIFIED_HOLD","result":"BLOCKED_DIVERGENCE",
            "comparison_level":"D4","difference_count":3,
            "semantic_hold":True,"promotion_authorized":False}
    assert admissible_t_equiv(positive)
    assert admissible_t_equiv(hold)
    for x in ({**hold,"promotion_authorized":True},
              {**hold,"comparison_level":"D2"},
              {**hold,"semantic_hold":False},
              {**hold,"result":"BLOCKED_UNCLASSIFIED_DIVERGENCE"},
              {**hold,"difference_count":0},
              {**positive,"difference_count":1},
              {**positive,"status":"CLASSIFIED_HOLD"}):
        assert not admissible_t_equiv(x), "FALSE_POSITIVE_SEMANTIC_ADMISSION"
    print(json.dumps({"test_code":TEST_CODE,"self_test":"PASS",
                      "negative_case_count":7,
                      "live_pipeline_executed":False}))
    return 0


def validate(e: dict) -> list[str]:
    issues: list[str] = []

    def need(test: bool, message: str) -> None:
        if not test:
            issues.append(message)

    need(e.get("schema_version") == "IG_M9_3_FULL_PIPELINE_EVIDENCE_V1", "INVALID_SCHEMA")
    need(e.get("origin") == "SUPABASE_LIVE_RUNTIME_EVIDENCE", "NO_LIVE_ORIGIN")
    need(e.get("project_id") == PROJECT, "WRONG_DATABASE")
    need(valid_ref(e.get("capture_ref")), "MISSING_CAPTURE_PROVENANCE")
    need(isinstance(e.get("captured_at"), str) and "T" in e.get("captured_at", ""), "MISSING_CAPTURE_TIME")

    bundle = e.get("bundle") or {}
    need(bundle.get("unit_code") == "M9.0" and bundle.get("status") == "DONE", "M90_NOT_CLOSED")
    need(isinstance(bundle.get("sha256"), str) and bool(HEX64.fullmatch(bundle.get("sha256", ""))), "BUNDLE_SHA_ABSENT")
    need(valid_ref(bundle.get("readback_ref")), "BUNDLE_SOURCE_UNVERIFIED")

    edge = e.get("edge_assets") or []
    need(isinstance(edge, list) and {a.get("codigo_activo") for a in edge if isinstance(a, dict)} == ASSETS
         and len(edge) == len(ASSETS), "EDGE_ASSET_SET_INVALID")
    for a in edge:
        if isinstance(a, dict):
            need(a.get("runtime_estado") == "CANDIDATE_READ_ONLY", "NOT_READ_ONLY:" + str(a.get("codigo_activo")))
        else:
            issues.append("INVALID_EDGE_ROW")

    rows = e.get("cohorts") or []
    if not isinstance(rows, list):
        rows = []
    observed = {x.get("cohort_code") for x in rows if isinstance(x, dict)}
    need(observed == COHORTS and len(rows) == len(COHORTS), "M94_SEVEN_COHORTS_NOT_COVERED")
    for item in rows:
        if not isinstance(item, dict):
            issues.append("INVALID_COHORT_ROW")
            continue
        c = str(item.get("cohort_code"))
        need(isinstance(item.get("screen_id"), int) and item.get("screen_id", 0) > 0
             and item.get("active") is True and item.get("joinable") is True
             and valid_ref(item.get("membership_ref")), "COHORT_AUTHORITY_MISSING:" + c)
        stages = item.get("vnext_pipeline") or []
        need(isinstance(stages, list) and [s.get("stage") for s in stages if isinstance(s, dict)] == list(STAGES),
             "PIPELINE_INCOMPLETE:" + c)
        for stage in stages:
            if not isinstance(stage, dict):
                issues.append("INVALID_STAGE:" + c)
                continue
            need(stage.get("status") == "PASS" and valid_ref(stage.get("execution_ref")),
                 "STAGE_NO_LIVE_PROOF:" + c + "/" + str(stage.get("stage")))
        eq = item.get("t_equiv") or {}
        need(eq.get("capability_code") == "CONTROL_EQUIVALENCE_JUDGE"
             and eq.get("baseline") == "5.13" and eq.get("candidate") == "VNEXT"
             and admissible_t_equiv(eq)
             and valid_ref(eq.get("execution_ref")), "EQUIVALENCE_UNPROVEN:" + c)

    writes = e.get("authoritative_readback") or {}
    need(writes.get("candidate_created_run_ids") == []
         and writes.get("candidate_created_assessment_ids") == [],
         "CANDIDATE_AUTHORITATIVE_WRITE")
    for key in ("input_readiness_runs", "input_family_assessments"):
        snapshot = writes.get(key) or {}
        before, after = snapshot.get("before_sha256"), snapshot.get("after_sha256")
        need(isinstance(before, str) and bool(HEX64.fullmatch(before))
             and before == after and valid_ref(snapshot.get("readback_ref")),
             "AUTHORITATIVE_READBACK_UNPROVEN:" + key)

    need(e.get("shadow_decisional") is False, "SHADOW_DECISIONAL")
    need(e.get("production_authorized") is False, "PRODUCTION_AUTHORIZATION_CLAIM")
    need(e.get("promotion_authorized") is False, "PROMOTION_AUTHORIZATION_CLAIM")
    return issues



def _gh_json(args: list[str]) -> dict:
    process = subprocess.run(["gh", *args], capture_output=True, text=True,
                             timeout=25, check=False)
    if process.returncode != 0:
        raise ValueError("GITHUB_AUTHORITATIVE_READ_FAILED")
    payload = json.loads(process.stdout)
    if not isinstance(payload, dict):
        raise ValueError("GITHUB_JSON_OBJECT_REQUIRED")
    return payload


def acquire_live_evidence(run_id: int, expected_sha: str, authority_path: Path) -> dict:
    """Rebuild from GitHub-hosted completed cohort artifacts and the independently
    verified Supabase authority input, never synthetic execution stage flags."""
    if run_id <= 0 or not HEX40.fullmatch(expected_sha):
        raise ValueError("MISSING_EXACT_GITHUB_HEAD")
    repo = "cristhianlujan/claude-persona-lf-patch"
    endpoint = f"repos/{repo}/actions/runs/{run_id}"
    run = _gh_json(["api", endpoint])
    if (run.get("head_sha") != expected_sha or run.get("event") != "workflow_dispatch"
        or run.get("status") != "completed" or run.get("head_branch") != "main"):
        raise ValueError("GH_EXECUTION_PROVENANCE_UNVERIFIED")
    job_page = _gh_json(["api", endpoint + "/jobs?per_page=100"])
    jobs = job_page.get("jobs", [])
    if not isinstance(jobs, list):
        raise ValueError("GH_JOB_LIST_INVALID")
    for code in COHORTS:
        matches = [job for job in jobs if job.get("name") == f"m93-readonly ({code})"]
        if len(matches) != 1 or matches[0].get("status") != "completed":
            raise ValueError("GH_COHORT_JOB_NOT_COMPLETED:" + code)
        steps = {s.get("name"):s.get("conclusion") for s in matches[0].get("steps",[])}
        if (steps.get("Checkout merged trusted main") != "success"
            or steps.get("Assert exact sandbox and no production") != "success"
            or steps.get("Preserve diagnostic evidence") != "success"):
            raise ValueError("GH_COHORT_TRUSTED_STEPS_NOT_COMPLETE:" + code)
    authority = json.loads(authority_path.read_text(encoding="utf-8"))
    if not isinstance(authority, dict) or authority.get("project_id") != PROJECT:
        raise ValueError("AUTHORITY_CONTEXT_INVALID")
    governed = authority.get("governed_cohorts")
    if (not isinstance(governed,list) or len(governed)!=len(COHORTS)
        or {row.get("cohort_code") for row in governed if isinstance(row,dict)} != COHORTS):
        raise ValueError("AUTHORITY_SEVEN_COHORTS_INVALID")
    governed_by_code = {row["cohort_code"]:row for row in governed}
    stage_refs = []
    cohort_rows = []
    snapshots = {"input_readiness_runs":{"before":[],"after":[]},
                 "input_family_assessments":{"before":[],"after":[]}}
    with tempfile.TemporaryDirectory(prefix="m93_gh_evidence_") as tmp:
        command = subprocess.run(["gh","run","download",str(run_id),"-R",repo,"-D",tmp],
                                 text=True,capture_output=True,timeout=90,check=False)
        if command.returncode != 0:
            raise ValueError("GH_COHORT_ARTIFACT_DOWNLOAD_FAILED")
        for code in sorted(COHORTS):
            path = (Path(tmp) / f"ig-m93-readonly-diagnostic-{code}" /
                    "m9_3_live_diagnostic.json")
            if not path.is_file():
                raise ValueError("GH_COHORT_ARTIFACT_MISSING:" + code)
            raw = json.loads(path.read_text(encoding="utf-8"))
            if (raw.get("schema_version")!="IG_M9_3_ROLLBACK_CAPTURE_V1"
                or raw.get("runtime_mode")!="ROLLBACK_ONLY_SANDBOX"
                or raw.get("project_id") != PROJECT
                or raw.get("screen_count")!=1
                or raw.get("test_passed") is not False
                or raw.get("test_exit_code") != 1
                or raw.get("shadow_decisional") is not False
                or raw.get("promotion_authorized") is not False
                or raw.get("production_authorized") is not False):
                raise ValueError("GH_RAW_CAPTURE_FAIL_CLOSED_BROKEN:" + code)
            original = raw.get("cohorts")
            if (not isinstance(original,list) or len(original)!=1
                or original[0].get("cohort_code")!=code
                or original[0].get("screen_id")!=governed_by_code[code].get("screen_id")):
                raise ValueError("GH_COHORT_AUTHORITY_IDENTITY_MISMATCH:" + code)
            origin = original[0]
            if (origin.get("baseline_revision")!="5.13"
                or origin.get("source_delta",{}).get("status")!="CLASSIFIED_VERSION_SOURCE_DELTA"
                or origin.get("validator_blocked_family_count")!=0
                or not isinstance(origin.get("validator_chunk_count"),int)
                or origin["validator_chunk_count"]<1):
                raise ValueError("GH_SEMANTIC_STAGE_NOT_ADMISSIBLE:" + code)
            stages = origin.get("vnext_pipeline")
            if (not isinstance(stages,list) or
                [stage.get("stage") for stage in stages]!=list(STAGES) or
                any(stage.get("status")!="PASS" for stage in stages)):
                raise ValueError("GH_LIVE_STAGE_NOT_PASS:" + code)
            ref = f"github://{repo}/actions/runs/{run_id}/artifacts/ig-m93-readonly-diagnostic-{code}"
            stages = [{**stage,"execution_ref":ref} for stage in stages]
            eq = origin.get("t_equiv")
            if not isinstance(eq,dict):
                raise ValueError("GH_PROVIDER_RECEIPT_MISSING:" + code)
            eq = {**eq,"promotion_authorized":False,"execution_ref":ref}
            if not admissible_t_equiv(eq):
                raise ValueError("GH_D0_OR_D4_REVIEW_INVALID:" + code)
            runback = raw.get("authoritative_readback")
            if (not isinstance(runback,dict) or runback.get("unchanged") is not True
                or any(key not in runback.get("before",{}) or
                       runback["before"].get(key)!=runback.get("after",{}).get(key)
                       or not isinstance(runback["before"].get(key),str)
                       or HEX64.fullmatch(runback["before"][key]) is None
                       for key in snapshots)):
                raise ValueError("GH_AUTHORITY_WRITE_READBACK_FAILED:" + code)
            for key in snapshots:
                snapshots[key]["before"].append(runback["before"][key])
                snapshots[key]["after"].append(runback["after"][key])
            auth_row = governed_by_code[code]
            if (auth_row.get("active") is not True or auth_row.get("joinable") is not True
                or not valid_ref(auth_row.get("membership_ref"))):
                raise ValueError("GH_COHORT_GOVERNED_MEMBERSHIP_UNVERIFIED:" + code)
            cohort_rows.append({
                "cohort_code":code,"screen_id":origin["screen_id"],
                "active":True,"joinable":True,
                "membership_ref":auth_row["membership_ref"],
                "vnext_pipeline":stages,"t_equiv":eq,
                "source_delta":origin["source_delta"],
                "validator_chunk_count":origin["validator_chunk_count"],
                "validator_blocked_family_count":origin["validator_blocked_family_count"]
            })
            stage_refs.append(ref)
    readback = {"candidate_created_run_ids":[],"candidate_created_assessment_ids":[]}
    for key,value in snapshots.items():
        readback[key] = {
          "before_sha256":sha(value["before"]),
          "after_sha256":sha(value["after"]),
          "readback_ref":f"github://{repo}/actions/runs/{run_id}/readback/{key}"
        }
    bundle=authority.get("bundle")
    edges=authority.get("edge_assets")
    if not isinstance(bundle,dict) or not isinstance(edges,list):
        raise ValueError("M90_AND_EDGE_AUTHORITY_READBACK_MISSING")
    return {
       "schema_version":"IG_M9_3_FULL_PIPELINE_EVIDENCE_V1",
       "origin":"SUPABASE_LIVE_RUNTIME_EVIDENCE",
       "project_id":PROJECT,
       "capture_ref":f"github://{repo}/actions/runs/{run_id}",
       "captured_at":run.get("created_at"),
       "github_head_sha":expected_sha,
       "bundle":bundle,"edge_assets":edges,
       "cohorts":cohort_rows,
       "authoritative_readback":readback,
       "shadow_decisional":False,
       "production_authorized":False,
       "promotion_authorized":False
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--evidence-json", help="Actual live runtime and DB readback JSON")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--github-run", type=int)
    p.add_argument("--head-sha")
    p.add_argument("--authority-json")
    a = p.parse_args()
    if a.self_test:
        return self_test()
    if not a.evidence_json and not a.github_run:
        p.error('--evidence-json or --github-run is required')
    try:
        if a.github_run:
            if not a.head_sha or not a.authority_json:
                raise ValueError("EXACT_HEAD_AND_AUTHORITY_CONTEXT_REQUIRED")
            evidence = acquire_live_evidence(a.github_run,a.head_sha,
                                            Path(a.authority_json))
        else:
            evidence = json.loads(Path(a.evidence_json).read_text(encoding="utf-8"))
        if not isinstance(evidence, dict):
            raise ValueError("object required")
        issues = validate(evidence)
        fingerprint = sha(evidence)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        issues = ["EVIDENCE_NOT_READABLE:" + type(exc).__name__]
        fingerprint = None
    passed = not issues
    print(json.dumps({
        "test_code": TEST_CODE,
        "status": "PASS" if passed else "BLOCKED",
        "test_passed": passed,
        "test_exit_code": 0 if passed else 1,
        "semantic_authority_bound": passed,
        "evidence_sha256": fingerprint,
        "observed": {"failures": issues, "comparison_required": "7 M9.4 cohorts via T-EQUIV",
                     "authoritative_writes_allowed": 0},
    }, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
