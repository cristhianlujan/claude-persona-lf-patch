#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "LF_EXTERNAL_CI_RECORDER_REQUEST_V1"
RECORDER = "public.lf_record_external_ci_suite_evidence_v1"


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit("LF_EXTERNAL_CI_RECORDER_MANIFEST_NOT_OBJECT")
    return value


def stable_test_code(test_file: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9]+", "_", Path(test_file).stem).strip("_").upper() or "TEST"
    digest = sha256_text(test_file)[:12].upper()
    return f"{stem[:40]}-{digest}"


def _request_json(url: str, token: str) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "lf-external-ci-recorder-payload-v1",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        body = response.read().decode("utf-8")
    value = json.loads(body)
    if not isinstance(value, dict):
        raise ValueError("GitHub jobs response is not an object")
    return value


def resolve_job_id(*, repository: str, run_id: int, job_display_name: str, token: str) -> tuple[int | None, str | None]:
    if not repository or "/" not in repository:
        return None, "REPOSITORY_INVALID"
    if run_id <= 0:
        return None, "RUN_ID_INVALID"
    if not job_display_name:
        return None, "JOB_DISPLAY_NAME_MISSING"
    if not token:
        return None, "GITHUB_TOKEN_MISSING"
    url = f"https://api.github.com/repos/{repository}/actions/runs/{run_id}/jobs?filter=latest&per_page=100"
    try:
        payload = _request_json(url, token)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
        return None, f"JOB_LOOKUP_FAILED:{type(exc).__name__}"
    jobs = payload.get("jobs")
    if not isinstance(jobs, list):
        return None, "JOB_LOOKUP_SHAPE_INVALID"
    exact = [job for job in jobs if isinstance(job, dict) and job.get("name") == job_display_name]
    if len(exact) != 1:
        return None, f"JOB_MATCH_COUNT:{len(exact)}"
    job_id = exact[0].get("id")
    if not isinstance(job_id, int) or job_id <= 0:
        return None, "JOB_ID_INVALID"
    return job_id, None


def build_request(*, manifest: dict[str, Any], repository: str, workflow_name: str, job_name: str, run_id: int, job_id: int | None) -> dict[str, Any]:
    blockers: list[str] = []
    suite_code = str(manifest.get("suite_code") or "").strip()
    source_sha = str(manifest.get("source_sha") or "").strip().lower()
    tested_sha = str(manifest.get("tested_sha") or "").strip().lower()
    test_pattern = str(manifest.get("test_pattern") or "").strip()
    manifest_sha256 = str(manifest.get("manifest_sha256") or "").strip().lower()
    failures = manifest.get("failures")
    control_errors = manifest.get("control_errors")

    if not suite_code:
        blockers.append("SUITE_CODE_MISSING")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        blockers.append("SOURCE_SHA_INVALID")
    if not re.fullmatch(r"[0-9a-f]{40}", tested_sha):
        blockers.append("TESTED_SHA_INVALID")
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha256):
        blockers.append("MANIFEST_SHA256_INVALID")
    if not repository or "/" not in repository:
        blockers.append("REPOSITORY_INVALID")
    if not workflow_name:
        blockers.append("WORKFLOW_NAME_MISSING")
    if not job_name:
        blockers.append("JOB_NAME_MISSING")
    if run_id <= 0:
        blockers.append("RUN_ID_INVALID")
    if job_id is None or job_id <= 0:
        blockers.append("JOB_ID_UNRESOLVED")
    if not test_pattern:
        blockers.append("TEST_PATTERN_MISSING")
    if not isinstance(failures, list):
        blockers.append("FAILURES_NOT_ARRAY")
        failures = []
    if not isinstance(control_errors, list):
        blockers.append("CONTROL_ERRORS_NOT_ARRAY")
        control_errors = []

    tests = sorted(path for path in glob.glob(test_pattern, recursive=True) if Path(path).is_file())
    expected_test_count = manifest.get("test_count")
    if not isinstance(expected_test_count, int) or expected_test_count != len(tests):
        blockers.append(f"TEST_COUNT_MISMATCH:{expected_test_count}:{len(tests)}")

    failures_by_file: dict[str, dict[str, Any]] = {}
    for item in failures:
        if not isinstance(item, dict):
            blockers.append("FAILURE_NOT_OBJECT")
            continue
        test_file = str(item.get("test_file") or "")
        if not test_file:
            blockers.append("FAILURE_TEST_FILE_MISSING")
            continue
        if test_file in failures_by_file:
            blockers.append(f"DUPLICATE_FAILURE:{test_file}")
            continue
        failures_by_file[test_file] = item

    for test_file in sorted(set(failures_by_file) - set(tests)):
        blockers.append(f"FAILURE_OUTSIDE_CASESET:{test_file}")
    if control_errors:
        blockers.append("CONTROL_ERRORS_PRESENT")

    results: list[dict[str, Any]] = []
    case_catalog: list[dict[str, str]] = []
    for test_file in tests:
        test_code = stable_test_code(test_file)
        case_catalog.append({"test_code": test_code, "test_file": test_file})
        failure = failures_by_file.get(test_file)
        if failure is None:
            results.append({
                "test_code": test_code,
                "status": "PASS",
                "actual_output": {"exit_code": 0, "diagnostic_complete": True, "test_file": test_file},
                "evidence_payload": {
                    "evidence_schema_version": "lf-gate-error-recorder-case/v1",
                    "manifest_sha256": manifest_sha256,
                    "test_file": test_file,
                    "source_sha": source_sha,
                    "tested_sha": tested_sha,
                },
            })
            continue
        results.append({
            "test_code": test_code,
            "status": "FAIL",
            "actual_output": {
                "exit_code": failure.get("exit_code"),
                "error_code": failure.get("error_class") or "PROCESS_EXIT",
                "error_detail": failure.get("error_summary") or "",
                "assertion_text": failure.get("assertion_text"),
                "diagnostic_complete": failure.get("diagnostic_complete") is True,
                "test_file": test_file,
            },
            "evidence_payload": {
                "evidence_schema_version": "lf-gate-error-recorder-case/v1",
                "manifest_sha256": manifest_sha256,
                "failure_id": failure.get("failure_id"),
                "test_file": test_file,
                "source_sha": source_sha,
                "tested_sha": tested_sha,
                "stdout_path": failure.get("stdout_path"),
                "stdout_sha256": failure.get("stdout_sha256"),
                "stderr_path": failure.get("stderr_path"),
                "stderr_sha256": failure.get("stderr_sha256"),
                "traceback_path": failure.get("traceback_path"),
                "traceback_sha256": failure.get("traceback_sha256"),
            },
        })

    rpc_args = {
        "p_suite_code": suite_code,
        "p_repository": repository,
        "p_workflow_name": workflow_name,
        "p_job_name": job_name,
        "p_source_workflow_run_id": run_id,
        "p_source_job_id": job_id,
        "p_source_commit_sha": tested_sha,
        "p_results": results,
        "p_actor_execution_id": f"GITHUB_ACTIONS:{repository}:{run_id}:{job_id}" if job_id and repository and run_id > 0 else None,
    }
    request = {
        "schema_version": SCHEMA_VERSION,
        "recorder": RECORDER,
        "recording_ready": not blockers,
        "recording_blockers": blockers,
        "source_manifest": {
            "schema_version": manifest.get("schema_version"),
            "manifest_sha256": manifest_sha256,
            "source_sha": source_sha,
            "tested_sha": tested_sha,
            "diagnostic_complete": manifest.get("diagnostic_complete") is True,
        },
        "case_catalog": case_catalog,
        "rpc_args": rpc_args,
    }
    request["request_sha256"] = sha256_text(canonical_json(request))
    return request


def write_request(path: Path, request: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(request, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build compact request for lf_record_external_ci_suite_evidence_v1")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--workflow-name", default=os.environ.get("GITHUB_WORKFLOW", ""))
    parser.add_argument("--job-name", default=os.environ.get("GITHUB_JOB", ""))
    parser.add_argument("--job-display-name", default="")
    parser.add_argument("--run-id", type=int, default=int(os.environ.get("GITHUB_RUN_ID", "0") or 0))
    parser.add_argument("--source-job-id", type=int)
    parser.add_argument("--github-token", default=os.environ.get("GH_TOKEN", "") or os.environ.get("GITHUB_TOKEN", ""))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = read_json(Path(args.manifest))
    job_id = args.source_job_id
    job_lookup_error = None
    if job_id is None:
        job_id, job_lookup_error = resolve_job_id(
            repository=args.repository,
            run_id=args.run_id,
            job_display_name=args.job_display_name,
            token=args.github_token,
        )
    request = build_request(
        manifest=manifest,
        repository=args.repository,
        workflow_name=args.workflow_name,
        job_name=args.job_name,
        run_id=args.run_id,
        job_id=job_id,
    )
    if job_lookup_error and "JOB_ID_UNRESOLVED" in request["recording_blockers"]:
        request["recording_blockers"].append(job_lookup_error)
        request["request_sha256"] = sha256_text(canonical_json({k: v for k, v in request.items() if k != "request_sha256"}))
    write_request(Path(args.output), request)
    print(f"LF_EXTERNAL_CI_RECORDER_REQUEST={args.output}")
    print(f"LF_EXTERNAL_CI_RECORDER_READY={str(request['recording_ready']).lower()}")
    print(f"LF_EXTERNAL_CI_RECORDER_CASE_COUNT={len(request['case_catalog'])}")
    print(f"LF_EXTERNAL_CI_RECORDER_REQUEST_SHA256={request['request_sha256']}")
    if request["recording_blockers"]:
        print("LF_EXTERNAL_CI_RECORDER_BLOCKERS=" + "|".join(request["recording_blockers"]))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
