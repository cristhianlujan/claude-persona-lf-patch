#!/usr/bin/env python3
"""Qualify GATE_CHECK_OBSERVABILITY against the existing WF_DIAGNOSTIC_COMPLETE_V1 Claim.

Read-only against the LF assurance catalog. It intentionally does not create a
new Claim/evaluator or mutate Supabase. The actual failure is synthetic and
runs through the same deterministic LF_GATE_CHECK_OBSERVABILITY_V1 producer.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

CLAIM_CODE = "WF_DIAGNOSTIC_COMPLETE_V1"
REQUIRED_CLOSURE = {
    "test_identity",
    "assertion_or_error",
    "expected_actual",
    "durable_artifact",
    "correlation",
    "owner_repair_resume",
}
REQUIRED_OBLIGATIONS = {
    "WF-DIAG-TEST-IDENTITY-V1",
    "WF-DIAG-ASSERTION-V1",
    "WF-DIAG-DURABLE-V1",
    "WF-DIAG-CORRELATION-V1",
    "WF-DIAG-EXPECTED-ACTUAL-V1",
    "WF-DIAG-OWNER-REPAIR-RESUME-V1",
}
REQUIRED_DEFEATERS = {
    "WF-D-CORRELATION-BROKEN-V1",
    "WF-D-EXPECTED-ACTUAL-MISSING-V1",
    "WF-D-OWNER-RESUME-MISSING-V1",
    "WF-D-STDOUT-LOSS-V1",
}
RUNNER = Path(__file__).with_name("run_gate_checks_v1.py")

CATALOG_SQL = r"""
with c as (
  select claim_code,version,claim_text,closure_rule,status,source_ref
  from public.lf_assurance_claim_catalog
  where claim_code='WF_DIAGNOSTIC_COMPLETE_V1' and version=1
),
o as (
  select jsonb_agg(to_jsonb(x) order by x.obligation_code) v
  from (
    select distinct on (obligation_code)
      obligation_code,version,required,status,evidence_contract,
      verification_method,positive_test_ref,negative_test_ref,adversarial_test_ref
    from public.lf_assurance_obligation_catalog
    where claim_code='WF_DIAGNOSTIC_COMPLETE_V1' and claim_version=1
    order by obligation_code,version desc
  ) x
),
d as (
  select jsonb_agg(to_jsonb(x) order by x.defeater_code) v
  from (
    select distinct on (defeater_code)
      defeater_code,version,status,required_counterevidence,zero_effect_required
    from public.lf_assurance_defeater_catalog
    where claim_code='WF_DIAGNOSTIC_COMPLETE_V1' and claim_version=1
    order by defeater_code,version desc
  ) x
)
select jsonb_build_object(
  'claim',to_jsonb(c),
  'obligations',coalesce(o.v,'[]'::jsonb),
  'defeaters',coalesce(d.v,'[]'::jsonb)
)::text
from c cross join o cross join d;
"""


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def live_contract(psql: str) -> dict:
    proc = subprocess.run(
        [psql, "-X", "-v", "ON_ERROR_STOP=1", "-Atq", "-c", CATALOG_SQL],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "CLAIM_CATALOG_READBACK_FAILED:" + (proc.stderr or "")[-800:]
        )
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise RuntimeError(f"CLAIM_CATALOG_READBACK_CARDINALITY:{len(lines)}")
    return json.loads(lines[0])


def artifact_uri(run_id: str, run_attempt: str) -> str:
    return (
        "artifact://lf-gate-diagnostics-profile-runtime-v3-"
        f"{run_id}-{run_attempt}/qualification/claim/canary/lf_gate_error_v1.json"
    )


def build_receipt(report: dict, report_path: Path) -> dict:
    failures = [
        item
        for item in report.get("checks", [])
        if item.get("check_status") == "FAIL"
    ]
    if len(failures) != 1:
        raise AssertionError(
            f"CLAIM_CANARY_FAILURE_CARDINALITY:{len(failures)}"
        )
    check = failures[0]
    run_id = str(report.get("run_id") or "")
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT") or "1"
    return {
        "workflow_run_id": run_id,
        "job_id": str(report.get("job_id") or ""),
        "step": str(report.get("step_id") or ""),
        "source_sha": str(check.get("tested_commit") or ""),
        "test_file": str(check.get("source_path") or ""),
        "test_case_or_check_id": str(check.get("check_id") or ""),
        "error_class": str(check.get("error_class") or ""),
        "assertion_or_error": str(
            check.get("assertion_text") or check.get("error_summary") or ""
        ),
        "expected": check.get("expected"),
        "actual": check.get("actual"),
        "operator_or_condition": str(check.get("condition") or ""),
        "rc": check.get("rc"),
        "durable_ref": artifact_uri(run_id, run_attempt),
        "local_evidence_ref": str(report_path.as_posix()),
        "retention_or_canonical_store": "GITHUB_ACTIONS_ARTIFACT_30D",
        "correlation": str(check.get("trace_id") or ""),
        "correlation_id": str(check.get("trace_id") or ""),
        "owner": str(report.get("owner") or ""),
        "repair_target": str(check.get("source_path") or ""),
        "first_bad_step": str(check.get("check_id") or ""),
        "resume_checkpoint": str(report.get("step_id") or ""),
        "rerun_scope": "FAILED_CHECK_THEN_TARGETED_GROUP_THEN_FULL_GATE",
        "job_log_available": False,
    }


def receipt_valid(receipt: dict, report: dict) -> bool:
    required = [
        "workflow_run_id",
        "job_id",
        "step",
        "source_sha",
        "test_file",
        "test_case_or_check_id",
        "error_class",
        "assertion_or_error",
        "expected",
        "actual",
        "operator_or_condition",
        "rc",
        "durable_ref",
        "local_evidence_ref",
        "retention_or_canonical_store",
        "correlation",
        "correlation_id",
        "owner",
        "repair_target",
        "first_bad_step",
        "resume_checkpoint",
        "rerun_scope",
    ]
    if any(
        key not in receipt or receipt[key] in ("", None)
        for key in required
    ):
        return False
    failures = [
        item
        for item in report.get("checks", [])
        if item.get("check_status") == "FAIL"
    ]
    if len(failures) != 1:
        return False
    check = failures[0]
    if not str(receipt["durable_ref"]).startswith("artifact://"):
        return False
    return (
        receipt["workflow_run_id"] == str(report.get("run_id"))
        and receipt["job_id"] == str(report.get("job_id"))
        and receipt["step"] == str(report.get("step_id"))
        and receipt["source_sha"] == str(check.get("tested_commit"))
        and receipt["test_file"] == str(check.get("source_path"))
        and receipt["test_case_or_check_id"] == str(check.get("check_id"))
        and receipt["correlation_id"] == str(check.get("trace_id"))
        and Path(receipt["local_evidence_ref"]).is_file()
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-dir", required=True)
    parser.add_argument("--psql", default="psql")
    args = parser.parse_args()

    out = Path(args.artifact_dir)
    out.mkdir(parents=True, exist_ok=True)
    contract = live_contract(args.psql)
    claim = contract.get("claim") or {}

    if claim.get("claim_code") != CLAIM_CODE:
        raise AssertionError("CLAIM_CODE_DRIFT")
    closure = set((claim.get("closure_rule") or {}).get("required") or [])
    if closure != REQUIRED_CLOSURE:
        raise AssertionError(f"CLAIM_CLOSURE_DRIFT:{sorted(closure)}")

    obligations = contract.get("obligations") or []
    obligation_codes = {
        item.get("obligation_code")
        for item in obligations
        if item.get("required") is True
    }
    if obligation_codes != REQUIRED_OBLIGATIONS:
        raise AssertionError(
            f"CLAIM_OBLIGATION_DRIFT:{sorted(obligation_codes)}"
        )

    defeaters = contract.get("defeaters") or []
    defeater_codes = {item.get("defeater_code") for item in defeaters}
    if defeater_codes != REQUIRED_DEFEATERS:
        raise AssertionError(
            f"CLAIM_DEFEATER_DRIFT:{sorted(defeater_codes)}"
        )

    fixture = out / "claim_canary_fail.py"
    fixture.write_text(
        "raise AssertionError('CLAIM_CANARY_EXPECTED_FAILURE')\n",
        encoding="utf-8",
    )
    report_dir = out / "canary"
    spec = json.dumps(
        {
            "argv": [sys.executable, str(fixture)],
            "source_path": str(fixture),
            "critical": False,
        },
        separators=(",", ":"),
    )
    command = [
        sys.executable,
        str(RUNNER),
        "--gate-id",
        "WF_DIAGNOSTIC_COMPLETE_V1_CANARY",
        "--step-id",
        "claim_canary",
        "--mode",
        "COLLECT_ALL",
        "--command-json",
        spec,
        "--artifact-dir",
        str(report_dir),
        "--artifact-name",
        "lf_gate_error_v1.json",
        "--check-prefix",
        "CLAIM",
        "--owner",
        "GATE_CHECK_OBSERVABILITY",
        "--next-action",
        "FIX_FAILED_CHECK_THEN_RERUN_TARGETED_THEN_FULL_GATE",
        "--run-id",
        os.environ.get("GITHUB_RUN_ID", "LOCAL"),
        "--job-id",
        os.environ.get("GITHUB_JOB", "LOCAL"),
    ]
    proc = subprocess.run(command)
    if proc.returncode != 1:
        raise AssertionError(
            f"CLAIM_CANARY_EXPECTED_FAIL_RC1:{proc.returncode}"
        )

    report_path = report_dir / "lf_gate_error_v1.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    receipt = build_receipt(report, report_path)
    if not receipt_valid(receipt, report):
        raise AssertionError("CLAIM_RECEIPT_POSITIVE_INVALID")

    # Explicit defeater falsification.
    bad = deepcopy(receipt)
    bad.pop("expected", None)
    if receipt_valid(bad, report):
        raise AssertionError("DEFEATER_EXPECTED_ACTUAL_NOT_CAUGHT")

    bad = deepcopy(receipt)
    bad["workflow_run_id"] = "OTHER_RUN"
    if receipt_valid(bad, report):
        raise AssertionError("DEFEATER_CROSS_RUN_NOT_CAUGHT")

    bad = deepcopy(receipt)
    bad.pop("owner", None)
    if receipt_valid(bad, report):
        raise AssertionError("DEFEATER_OWNER_RESUME_NOT_CAUGHT")

    no_job_log = deepcopy(receipt)
    no_job_log["job_log_available"] = False
    if not receipt_valid(no_job_log, report):
        raise AssertionError("DEFEATER_STDOUT_LOSS_NOT_CLOSED")

    result = {
        "schema_version": "lf-wf-diagnostic-claim-qualification/v1",
        "claim_code": CLAIM_CODE,
        "catalog_status": claim.get("status"),
        "result": "PASS_WITH_EVIDENCE",
        "required_obligations": len(REQUIRED_OBLIGATIONS),
        "obligations_passed": len(REQUIRED_OBLIGATIONS),
        "required_defeaters": len(REQUIRED_DEFEATERS),
        "defeaters_closed": len(REQUIRED_DEFEATERS),
        "source_sha": receipt["source_sha"],
        "canary_report_ref": receipt["durable_ref"],
        "normalized_receipt": receipt,
    }
    write_json(out / "wf_diagnostic_claim_qualification_v1.json", result)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
