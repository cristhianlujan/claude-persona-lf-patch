"""Deterministic validator for J12_GITHUB_INTEGRITY."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J12_GITHUB_INTEGRITY"


def _obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def _files(value: Any, name: str) -> dict[str, str]:
    if not isinstance(value, list):
        raise ValidationInputError(f"{name}_must_be_array")
    out: dict[str, str] = {}
    for item in value:
        if not isinstance(item, dict):
            raise ValidationInputError(f"{name}_item_must_be_object")
        path = item.get("path")
        sha = item.get("sha256")
        if not isinstance(path, str) or not path or not isinstance(sha, str) or len(sha) != 64:
            raise ValidationInputError(f"{name}_item_invalid")
        if path in out:
            raise ValidationInputError(f"{name}_duplicate_path:{path}")
        out[path] = sha
    return out


def validate_payload(payload: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    contract = _obj(payload.get("github_contract"), "github_contract")
    plan = _obj(payload.get("write_plan"), "write_plan")
    expected = set(plan.get("expected_files") or [])
    written = _files(payload.get("written_files"), "written_files")
    readback = _files(payload.get("readback_files"), "readback_files")
    canonical = _obj(payload.get("canonical_hash_map"), "canonical_hash_map")

    written_paths, readback_paths = set(written), set(readback)
    all_paths = expected | written_paths | readback_paths
    sha_mismatch = sum(1 for path in written_paths & readback_paths if written[path] != readback[path])
    content_mismatch = sum(
        1 for path in all_paths
        if path in readback and path in canonical and readback[path] != canonical[path]
    )
    checks = {
        "expected_written": len(expected - written_paths),
        "written_readback": len(written_paths - readback_paths),
        "unexpected_written_files": len(written_paths - expected),
        "missing_written_files": len(expected - written_paths),
        "sha_mismatches": sha_mismatch,
        "content_hash_mismatches": content_mismatch,
        "partial_write_detected": 1 if contract.get("partial_write_detected") is True else 0,
        "direct_main_write_detected": 1 if contract.get("direct_main_write_detected") is True else 0,
        "target_branch_mismatch": 0 if contract.get("target_branch") == contract.get("authorized_branch") else 1,
        "draft_pr_not_preserved": 0 if contract.get("draft_pr") is True else 1,
    }
    evidence = {
        "checks": checks,
        "repository": contract.get("repository"),
        "branch": contract.get("target_branch"),
        "commit_sha": contract.get("commit_sha"),
        "written_file_count": len(written),
        "readback_file_count": len(readback),
        "expected_file_count": len(expected),
        "sha_comparison": {"mismatches": sha_mismatch, "content_mismatches": content_mismatch},
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
        JUDGE, failed, evidence, refs or [f"file:{path}"], repairs,
        retry_count=retry, forced_result=forced,
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
    ))


def positive() -> dict[str, Any]:
    sha = "a" * 64
    return {
        "github_contract": {
            "repository": "owner/repo", "authorized_branch": "feat/r8", "target_branch": "feat/r8",
            "commit_sha": "b" * 40, "pr_number": 57, "draft_pr": True,
            "direct_main_write_detected": False, "partial_write_detected": False,
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
    good_checks, _ = validate_payload(good)
    bad_checks, _ = validate_payload(bad)
    result = {
        "positive_pass": all(v == 0 for v in good_checks.values()),
        "negative_rejected": bad_checks["sha_mismatches"] > 0 and bad_checks["target_branch_mismatch"] > 0,
        "positive_checks": good_checks,
        "negative_checks": bad_checks,
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["positive_pass"] and result["negative_rejected"] else 1


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
