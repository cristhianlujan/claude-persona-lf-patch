#!/usr/bin/env python3
"""Validate LF PASS candidate evidence against live GitHub state.

This gate does not grant PASS. It proves that a candidate references a merged
pull request and a completed successful workflow run. Supabase remains the
canonical state store and requires a separately recorded external verification
event before PASS_WITH_EVIDENCE can be persisted.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
AUDIT_CODE = re.compile(r"^A[0-9]{2}$")
REQUIRED_FIELDS = {
    "evidence_schema_version", "result", "repository", "audit_code",
    "relative_path", "artifact_sha256", "artifact_git_blob", "pr_number",
    "merge_commit_sha", "workflow_run_id", "workflow_name",
    "workflow_head_sha", "workflow_conclusion", "test_event_ids",
}


class EvidenceError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def validate_shape(data: dict[str, Any]) -> None:
    missing = sorted(REQUIRED_FIELDS - data.keys())
    require(not missing, f"missing required fields: {', '.join(missing)}")
    require(data["evidence_schema_version"] == "github-pass-evidence/v1", "invalid evidence_schema_version")
    require(data["result"] == "PASS_CANDIDATE", "result must be PASS_CANDIDATE")
    require(isinstance(data["repository"], str) and "/" in data["repository"], "repository must be owner/name")
    require(isinstance(data["audit_code"], str) and AUDIT_CODE.fullmatch(data["audit_code"]) is not None, "invalid audit_code")
    require(isinstance(data["relative_path"], str) and data["relative_path"].strip() != "", "relative_path is required")
    require(isinstance(data["artifact_sha256"], str) and SHA64.fullmatch(data["artifact_sha256"]) is not None, "invalid artifact_sha256")
    require(isinstance(data["artifact_git_blob"], str) and SHA40.fullmatch(data["artifact_git_blob"]) is not None, "invalid artifact_git_blob")
    require(isinstance(data["pr_number"], int) and data["pr_number"] > 0, "pr_number must be a positive integer")
    require(isinstance(data["merge_commit_sha"], str) and SHA40.fullmatch(data["merge_commit_sha"]) is not None, "invalid merge_commit_sha")
    require(isinstance(data["workflow_run_id"], int) and data["workflow_run_id"] > 0, "workflow_run_id must be a positive integer")
    require(isinstance(data["workflow_name"], str) and data["workflow_name"].strip() != "", "workflow_name is required")
    require(isinstance(data["workflow_head_sha"], str) and SHA40.fullmatch(data["workflow_head_sha"]) is not None, "invalid workflow_head_sha")
    require(data["workflow_conclusion"] == "success", "workflow_conclusion must be success")
    require(isinstance(data["test_event_ids"], list) and len(data["test_event_ids"]) > 0, "test_event_ids must be non-empty")
    require(all(isinstance(value, int) and value > 0 for value in data["test_event_ids"]), "test_event_ids must contain positive integers")
    require(len(set(data["test_event_ids"])) == len(data["test_event_ids"]), "test_event_ids must be unique")


def github_get(repository: str, endpoint: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/{endpoint.lstrip('/')}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "lf-pass-evidence-gate",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise EvidenceError(f"GitHub API {exc.code} for {endpoint}: {body[:300]}") from exc
    except urllib.error.URLError as exc:
        raise EvidenceError(f"GitHub API unavailable for {endpoint}: {exc.reason}") from exc


def validate_live(data: dict[str, Any], token: str) -> None:
    repository = data["repository"]
    pull = github_get(repository, f"pulls/{data['pr_number']}", token)
    require(pull.get("merged") is True, "pull request is not merged")
    require(pull.get("state") == "closed", "pull request is not closed")
    require(pull.get("merge_commit_sha") == data["merge_commit_sha"], "merge_commit_sha does not match GitHub")

    run = github_get(repository, f"actions/runs/{data['workflow_run_id']}", token)
    require(run.get("status") == "completed", "workflow run is not completed")
    require(run.get("conclusion") == "success", "workflow run did not conclude success")
    require(run.get("name") == data["workflow_name"], "workflow name does not match GitHub")
    require(run.get("head_sha") == data["workflow_head_sha"], "workflow head SHA does not match GitHub")
    require(run.get("repository", {}).get("full_name") == repository, "workflow repository does not match")


def load_candidate(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"{path}: invalid JSON: {exc}") from exc
    require(isinstance(value, dict), f"{path}: root must be an object")
    return value


def scan(directory: Path, token: str | None, expected_repository: str | None) -> int:
    if not directory.exists():
        print(f"NO_PASS_CANDIDATES: {directory} does not exist; no PASS promotion is authorized")
        return 0
    candidates = sorted(directory.glob("*.json"))
    if not candidates:
        print(f"NO_PASS_CANDIDATES: {directory} is empty; no PASS promotion is authorized")
        return 0
    require(bool(token), "GITHUB_TOKEN is required when PASS candidates exist")
    for path in candidates:
        data = load_candidate(path)
        validate_shape(data)
        if expected_repository:
            require(data["repository"] == expected_repository, f"{path}: repository differs from GITHUB_REPOSITORY")
        validate_live(data, token or "")
        print(f"PASS_EXTERNAL_GITHUB_EVIDENCE: {data['audit_code']} {path}")
    print(f"PASS_CANDIDATE_FILES_VALIDATED: {len(candidates)}")
    return 0


def self_test() -> None:
    valid: dict[str, Any] = {
        "evidence_schema_version": "github-pass-evidence/v1",
        "result": "PASS_CANDIDATE",
        "repository": "owner/repository",
        "audit_code": "A19",
        "relative_path": "example/path.md",
        "artifact_sha256": "a" * 64,
        "artifact_git_blob": "b" * 40,
        "pr_number": 123,
        "merge_commit_sha": "c" * 40,
        "workflow_run_id": 456,
        "workflow_name": "lf-contract-check",
        "workflow_head_sha": "d" * 40,
        "workflow_conclusion": "success",
        "test_event_ids": [1, 2, 3],
    }
    validate_shape(valid)
    mutations = [
        ("missing_merge", {"merge_commit_sha": None}),
        ("failed_workflow", {"workflow_conclusion": "failure"}),
        ("empty_tests", {"test_event_ids": []}),
        ("bad_sha", {"artifact_sha256": "not-a-sha"}),
        ("pass_instead_of_candidate", {"result": "PASS_WITH_EVIDENCE"}),
    ]
    rejected = 0
    for label, mutation in mutations:
        case = dict(valid)
        case.update(mutation)
        try:
            validate_shape(case)
        except EvidenceError:
            rejected += 1
            print(f"SELFTEST_NEGATIVE_REJECTED: {label}")
        else:
            raise AssertionError(f"negative case was accepted: {label}")
    require(rejected == len(mutations), "not all negative self-tests were rejected")
    print(f"SELFTEST_PASS: positive=1 negative={rejected}/{len(mutations)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--scan", type=Path)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
        if args.scan is not None:
            return scan(args.scan, os.environ.get("GITHUB_TOKEN"), args.repository)
        if not args.self_test and args.scan is None:
            parser.error("use --self-test and/or --scan")
    except EvidenceError as exc:
        print(f"FAIL_PASS_EVIDENCE_GATE: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
