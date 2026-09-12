"""Deterministic validator for J12_GITHUB_INTEGRITY."""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J12_GITHUB_INTEGRITY"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def _obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def _non_empty_text(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationInputError(f"{name}_must_be_non_empty_string")
    return value


def _files(value: Any, name: str) -> dict[str, str]:
    if not isinstance(value, list):
        raise ValidationInputError(f"{name}_must_be_array")
    if not value:
        raise ValidationInputError(f"{name}_empty")
    out: dict[str, str] = {}
    for item in value:
        if not isinstance(item, dict):
            raise ValidationInputError(f"{name}_item_must_be_object")
        path = item.get("path")
        sha = item.get("sha256")
        if not isinstance(path, str) or not path or not isinstance(sha, str) or not SHA256_RE.fullmatch(sha):
            raise ValidationInputError(f"{name}_item_invalid")
        if path in out:
            raise ValidationInputError(f"{name}_duplicate_path:{path}")
        out[path] = sha
    return out


def _expected_files(plan: dict[str, Any]) -> set[str]:
    raw = plan.get("expected_files")
    if not isinstance(raw, list):
        raise ValidationInputError("write_plan.expected_files_must_be_array")
    if not raw:
        raise ValidationInputError("write_plan.expected_files_empty")
    if any(not isinstance(path, str) or not path.strip() for path in raw):
        raise ValidationInputError("write_plan.expected_files_item_invalid")
    if len(raw) != len(set(raw)):
        raise ValidationInputError("write_plan.expected_files_duplicate")
    return set(raw)


def _canonical_hashes(value: Any) -> dict[str, str]:
    raw = _obj(value, "canonical_hash_map")
    if not raw:
        raise ValidationInputError("canonical_hash_map_empty")
    for path, sha in raw.items():
        if not isinstance(path, str) or not path or not isinstance(sha, str) or not SHA256_RE.fullmatch(sha):
            raise ValidationInputError("canonical_hash_map_item_invalid")
    return raw


def validate_payload(payload: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    required = ("github_contract", "write_plan", "canonical_hash_map", "written_files", "readback_files")
    missing = [key for key in required if key not in payload]
    if missing:
        raise ValidationInputError("github_integrity_required_inputs_missing:" + ",".join(missing))

    contract = _obj(payload["github_contract"], "github_contract")
    plan = _obj(payload["write_plan"], "write_plan")
    expected = _expected_files(plan)
    written = _files(payload["written_files"], "written_files")
    readback = _files(payload["readback_files"], "readback_files")
    canonical = _canonical_hashes(payload["canonical_hash_map"])

    repository = _non_empty_text(contract.get("repository"), "github_contract.repository")
    authorized_branch = _non_empty_text(contract.get("authorized_branch"), "github_contract.authorized_branch")
    target_branch = _non_empty_text(contract.get("target_branch"), "github_contract.target_branch")
    commit_sha = _non_empty_text(contract.get("commit_sha"), "github_contract.commit_sha")
    if not COMMIT_RE.fullmatch(commit_sha):
        raise ValidationInputError("github_contract.commit_sha_invalid")
    if not isinstance(contract.get("pr_number"), int) or contract["pr_number"] <= 0:
        raise ValidationInputError("github_contract.pr_number_invalid")
    if not isinstance(contract.get("draft_pr"), bool):
        raise ValidationInputError("github_contract.draft_pr_must_be_boolean")

    written_paths, readback_paths, canonical_paths = set(written), set(readback), set(canonical)
    all_paths = expected | written_paths | readback_paths
    sha_mismatch = sum(1 for path in written_paths & readback_paths if written[path] != readback[path])
    canonical_missing = len(expected - canonical_paths)
    content_mismatch = sum(
        1
        for path in all_paths
        if path in readback and path in canonical and readback[path] != canonical[path]
    )
    checks = {
        "expected_written": len(expected - written_paths),
        "written_readback": len(written_paths - readback_paths),
        "unexpected_written_files": len(written_paths - expected),
        "missing_written_files": len(expected - written_paths),
        "canonical_hash_missing": canonical_missing,
        "sha_mismatches": sha_mismatch,
        "content_hash_mismatches": content_mismatch,
        "partial_write_detected": 1 if contract.get("partial_write_detected") is True else 0,
        "direct_main_write_detected": 1 if contract.get("direct_main_write_detected") is True else 0,
        "target_branch_mismatch": 0 if target_branch == authorized_branch else 1,
        "draft_pr_not_preserved": 0 if contract.get("draft_pr") is True else 1,
    }
    evidence = {
        "checks": checks,
        "repository": repository,
        "branch": target_branch,
        "authorized_branch": authorized_branch,
        "commit_sha": commit_sha,
        "written_file_count": len(written),
        "readback_file_count": len(readback),
        "expected_file_count": len(expected),
        "canonical_file_count": len(canonical),
        "sha_comparison": {
            "mismatches": sha_mismatch,
            "content_mismatches": content_mismatch,
            "canonical_missing": canonical_missing,
        },
        "pr_number": contract.get("pr_number"),
        "draft_state": contract.get("draft_pr"),
    }
    return checks, evidence


def run(path: Path, refs: list[str], retry: int) -> int:
    payload = _obj(load_json(path), "input")
    checks, evidence = validate_payload(payload)
    evidence["input_path"] = str(path)
    failed = [key for key, value in checks.items() if value]
    repairs = [failure(key, "$", f"Repair GitHub integrity until {key}=0") for key in failed]
    forced = "FAIL" if checks["direct_main_write_detected"] or checks["partial_write_detected"] else None
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        refs or [f"file:{path}"],
        repairs,
        retry_count=retry,
        forced_result=forced,
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
    ))


def positive() -> dict[str, Any]:
    sha = "a" * 64
    return {
        "github_contract": {
            "repository": "owner/repo",
            "authorized_branch": "feat/r8",
            "target_branch": "feat/r8",
            "commit_sha": "b" * 40,
            "pr_number": 57,
            "draft_pr": True,
            "direct_main_write_detected": False,
            "partial_write_detected": False,
        },
        "write_plan": {"expected_files": ["a.md"]},
        "canonical_hash_map": {"a.md": sha},
        "written_files": [{"path": "a.md", "sha256": sha}],
        "readback_files": [{"path": "a.md", "sha256": sha}],
    }


def self_test() -> int:
    good = positive()
    bad = json.loads(json.dumps(good))
    bad["readback_files"][0]["sha256"] = "c" * 64
    bad["github_contract"]["target_branch"] = "main"
    missing_canonical = json.loads(json.dumps(good))
    missing_canonical["canonical_hash_map"] = {"other.md": "d" * 64}
    good_checks, _ = validate_payload(good)
    bad_checks, _ = validate_payload(bad)
    canonical_checks, _ = validate_payload(missing_canonical)
    blocked_cases: dict[str, bool] = {}
    for name, payload in {
        "empty_expected": {**good, "write_plan": {"expected_files": []}},
        "empty_canonical": {**good, "canonical_hash_map": {}},
        "empty_written": {**good, "written_files": []},
        "missing_repository": {**good, "github_contract": {key: value for key, value in good["github_contract"].items() if key != "repository"}},
    }.items():
        try:
            validate_payload(payload)
            blocked_cases[name] = False
        except ValidationInputError:
            blocked_cases[name] = True
    result = {
        "positive_pass": all(value == 0 for value in good_checks.values()),
        "negative_rejected": bad_checks["sha_mismatches"] > 0 and bad_checks["target_branch_mismatch"] > 0,
        "canonical_gap_rejected": canonical_checks["canonical_hash_missing"] > 0,
        "blocked_cases": blocked_cases,
        "positive_checks": good_checks,
        "negative_checks": bad_checks,
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["positive_pass"] and result["negative_rejected"] and result["canonical_gap_rejected"] and all(blocked_cases.values()) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    return run(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
