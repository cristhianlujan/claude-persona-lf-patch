#!/usr/bin/env python3
"""M10.4 CP3: verify genuine GitHub acceptance and adversarial rejection.

This test runs read-only against historical GitHub PR/check-run evidence.
It neither opens nor merges PRs, and never applies migrations.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys


def gh_json(repo: str, endpoint: str):
    p = subprocess.run(
        ["gh", "api", f"repos/{repo}/{endpoint}"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
    )
    if p.returncode != 0:
        raise RuntimeError("FAIL_CP3_GH_API:" + endpoint + ":" + p.stderr[:150])
    return json.loads(p.stdout)


def run_logs(repo: str, run_id: int) -> str:
    p = subprocess.run(
        ["gh", "run", "view", str(run_id), "-R", repo, "--log"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
    )
    if p.returncode != 0:
        raise RuntimeError("FAIL_CP3_RUN_LOG_READ:" + p.stderr[:150])
    return p.stdout


def assert_check(repo: str, sha: str, expected: str) -> None:
    rows = gh_json(repo, f"commits/{sha}/check-runs?per_page=100")
    checks = [c for c in rows.get("check_runs", []) if c.get("name") == "lf-independent-change-admission"]
    if not checks or not any(c.get("conclusion") == expected for c in checks):
        raise RuntimeError("FAIL_CP3_CHECK_RESULT:" + expected)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo", required=True)
    p.add_argument("--positive-pr", type=int, required=True)
    p.add_argument("--negative-pr", type=int, required=True)
    p.add_argument("--negative-run", type=int, required=True)
    args = p.parse_args()
    try:
        yes = gh_json(args.repo, f"pulls/{args.positive_pr}")
        no = gh_json(args.repo, f"pulls/{args.negative_pr}")
        if not yes.get("merged_at") or yes.get("state") != "closed":
            raise RuntimeError("FAIL_CP3_POSITIVE_PR_NOT_MERGED")
        if no.get("merged_at") or no.get("state") != "closed" or not no.get("draft"):
            raise RuntimeError("FAIL_CP3_NEGATIVE_NOT_CLOSED_UNMERGED_DRAFT")
        if any(label["name"] == "ready-to-merge" for label in no.get("labels", [])):
            raise RuntimeError("FAIL_CP3_NEGATIVE_PR_TRAIN_ADMISSION")
        assert_check(args.repo, yes["head"]["sha"], "success")
        assert_check(args.repo, no["head"]["sha"], "failure")
        logs = run_logs(args.repo, args.negative_run)
        expected_code = "FAIL_M104_FROZEN_LEGACY_MUTATION:"
        if expected_code not in logs:
            raise RuntimeError("FAIL_CP3_WRONG_NEGATIVE_CAUSE")
        if "programacion.fn_input_actionable_remediation_summary_v1" not in logs:
            raise RuntimeError("FAIL_CP3_WRONG_FROZEN_TARGET")
        result = {
            "schema_version": "IG_M104_NEG_NEW_MIGRATION_TEST_V1",
            "test_code": "ENG_M10_4_NEG_NEW_MIGRATION",
            "status": "PASS",
            "test_exit_code": 0,
            "semantic_authority_bound": True,
            "adversarial_case_executed": True,
            "test_passed": True,
            "positive_pr": args.positive_pr,
            "positive_sha": yes["head"]["sha"],
            "positive_ci": "SUCCESS",
            "negative_pr": args.negative_pr,
            "negative_sha": no["head"]["sha"],
            "negative_ci": "FAILURE_EXPECTED",
            "negative_failure_code": expected_code[:-1],
            "negative_source_applied": False,
            "negative_pr_merged": False,
            "negative_log_run": args.negative_run,
        }
        print(json.dumps(result, sort_keys=True))
        return 0
    except (RuntimeError, KeyError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
