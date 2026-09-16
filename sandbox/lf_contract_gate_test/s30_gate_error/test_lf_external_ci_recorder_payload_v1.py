#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "gobernanza" / "judges" / "lf_external_ci_recorder_payload_v1.py"
spec = importlib.util.spec_from_file_location("lf_external_ci_recorder_payload_v1", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

with tempfile.TemporaryDirectory(prefix="lf-external-ci-recorder-v1-") as td:
    root = Path(td)
    tests = root / "tests"
    tests.mkdir()
    pass_file = tests / "test_pass.py"
    fail_file = tests / "test_fail.py"
    pass_file.write_text("print('ok')\n", encoding="utf-8")
    fail_file.write_text("raise ValueError('boom')\n", encoding="utf-8")
    pattern = str(tests / "test_*.py")
    failure = {
        "failure_id": "f" * 64,
        "test_file": str(fail_file),
        "exit_code": 1,
        "error_class": "ValueError",
        "error_summary": "ValueError: boom",
        "assertion_text": None,
        "stdout_path": "failures/fail.stdout.log",
        "stdout_sha256": "1" * 64,
        "stderr_path": "failures/fail.stderr.log",
        "stderr_sha256": "2" * 64,
        "traceback_path": "failures/fail.stderr.log",
        "traceback_sha256": "2" * 64,
        "diagnostic_complete": True,
    }
    manifest = {
        "schema_version": "LF_GATE_ERROR_V1",
        "suite_code": "PROFILE_RUNTIME_V3",
        "source_sha": "a" * 40,
        "tested_sha": "b" * 40,
        "test_pattern": pattern,
        "test_count": 2,
        "failure_count": 1,
        "control_errors": [],
        "failures": [failure],
        "diagnostic_complete": True,
        "manifest_sha256": "c" * 64,
    }
    request = mod.build_request(
        manifest=manifest,
        repository="cristhianlujan/claude-persona-lf-patch",
        workflow_name="Validate LF Packs",
        job_name="validate-lf-packs",
        run_id=123,
        job_id=456,
    )
    assert request["schema_version"] == "LF_EXTERNAL_CI_RECORDER_REQUEST_V1", request
    assert request["recorder"] == "public.lf_record_external_ci_suite_evidence_v1", request
    assert request["recording_ready"] is True, request
    assert request["recording_blockers"] == [], request
    assert len(request["case_catalog"]) == 2, request
    results = request["rpc_args"]["p_results"]
    assert len(results) == 2, results
    assert {r["status"] for r in results} == {"PASS", "FAIL"}, results
    failed = next(r for r in results if r["status"] == "FAIL")
    assert failed["actual_output"]["error_code"] == "ValueError", failed
    assert failed["evidence_payload"]["traceback_sha256"] == "2" * 64, failed
    assert request["rpc_args"]["p_source_commit_sha"] == "b" * 40, request
    assert request["rpc_args"]["p_actor_execution_id"] == (
        "GITHUB_ACTIONS:cristhianlujan/claude-persona-lf-patch:123:456"
    ), request
    assert len(request["request_sha256"]) == 64, request

    blocked = mod.build_request(
        manifest=manifest,
        repository="cristhianlujan/claude-persona-lf-patch",
        workflow_name="Validate LF Packs",
        job_name="validate-lf-packs",
        run_id=123,
        job_id=None,
    )
    assert blocked["recording_ready"] is False, blocked
    assert "JOB_ID_UNRESOLVED" in blocked["recording_blockers"], blocked

    bad_manifest = json.loads(json.dumps(manifest))
    bad_manifest["test_count"] = 99
    mismatch = mod.build_request(
        manifest=bad_manifest,
        repository="cristhianlujan/claude-persona-lf-patch",
        workflow_name="Validate LF Packs",
        job_name="validate-lf-packs",
        run_id=123,
        job_id=456,
    )
    assert mismatch["recording_ready"] is False, mismatch
    assert any(code.startswith("TEST_COUNT_MISMATCH:") for code in mismatch["recording_blockers"]), mismatch

print("PASS_LF_EXTERNAL_CI_RECORDER_PAYLOAD_V1 cases=complete_case_set,fail_evidence,job_binding,count_mismatch")
