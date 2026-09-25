#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

MODULE = Path(__file__).with_name("lf_contract_plan_trace_wiring_v1.py")
spec = importlib.util.spec_from_file_location("lf_contract_plan_trace_wiring_v1", MODULE)
assert spec and spec.loader
wiring = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wiring)

SOURCE = "a" * 40
EVIDENCE = "b" * 64
RUN_ID = "123456"
ATTEMPT = 2
REPO = "cristhianlujan/claude-persona-lf-patch"


def request() -> dict:
    return {
        "schema_version": "lf-contract-plan-trace/v1",
        "execution_id": f"EXEC-LF-CONTRACT-CHECK-{RUN_ID}-{ATTEMPT}",
        "operation_code": "GITHUB_CONTRACT_GATE_LF",
        "target_type": "REPOSITORY_GOVERNED_PATHS",
        "target_code": f"LF_CONTRACT_CHECK_RUN_{RUN_ID}_{ATTEMPT}",
        "target_repo": REPO,
        "target_path": ".github/workflows/lf-contract-check.yml",
        "idempotency_key": f"LF-CONTRACT-CHECK:{RUN_ID}:{ATTEMPT}:{SOURCE}",
        "request_sha256": EVIDENCE,
        "manifest": {
            "schema_version": "lf-contract-plan-trace/v1",
            "scope": "LF_CONTRACT_PLAN_TRACE",
            "source_commit": SOURCE,
            "github_run_id": RUN_ID,
            "github_run_attempt": ATTEMPT,
            "evidence_sha256": EVIDENCE,
        },
    }


def expect_error(code: str, fn) -> None:
    try:
        fn()
    except wiring.WiringError as exc:
        assert str(exc) == code, (str(exc), code)
    else:
        raise AssertionError(f"expected {code}")


def main() -> int:
    checks = 0

    validated = wiring.validate_trace_request(
        request(), exact_source=SOURCE, repository=REPO, run_id=RUN_ID, run_attempt=ATTEMPT
    )
    assert validated["execution_id"] == f"EXEC-LF-CONTRACT-CHECK-{RUN_ID}-{ATTEMPT}"
    checks += 1

    bad = copy.deepcopy(request())
    bad["request_sha256"] = "c" * 64
    expect_error(
        "FAIL_PLAN_TRACE_WIRING_REQUEST_EVIDENCE_MISMATCH",
        lambda: wiring.validate_trace_request(bad),
    )
    checks += 1

    bad = copy.deepcopy(request())
    bad["execution_id"] = "EXEC-LF-CONTRACT-CHECK-WRONG"
    expect_error(
        "FAIL_PLAN_TRACE_WIRING_EXECUTION_DERIVATION",
        lambda: wiring.validate_trace_request(bad),
    )
    checks += 1

    assert_sql = wiring.render_assert_sql(request())
    assert "fn_lf_operation_reserve_execution_v1" not in assert_sql
    assert "PASS_LF_CONTRACT_PLAN_TRACE_READBACK" in assert_sql
    assert "status<>'IN_PROGRESS'" in assert_sql
    checks += 1

    completed = wiring.render_close_sql(request(), job_status="success")
    assert "set status='COMPLETED'" in completed
    assert "LF_CONTRACT_PLAN_TRACE_ALREADY_BLOCKED" in completed
    assert "LF_CONTRACT_PLAN_TRACE_WIRING_V1" in completed
    checks += 1

    blocked = wiring.render_close_sql(request(), job_status="failure")
    assert "set status='BLOCKED'" in blocked
    assert "COMPLETED_CANNOT_DOWNGRADE" in blocked
    checks += 1

    cancelled = wiring.render_close_sql(request(), job_status="cancelled")
    assert "set status='BLOCKED'" in cancelled
    checks += 1

    expect_error(
        "FAIL_PLAN_TRACE_WIRING_EXACT_HEAD",
        lambda: wiring.validate_trace_request(request(), exact_source="d" * 40),
    )
    checks += 1

    print(f"PASS_LF_CONTRACT_PLAN_TRACE_WIRING_TESTS={checks}/8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
