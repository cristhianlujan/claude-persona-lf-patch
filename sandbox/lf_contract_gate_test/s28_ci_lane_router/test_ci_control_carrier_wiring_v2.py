#!/usr/bin/env python3
"""Independent structural judge for CI carrier wiring and Bootstrap retirement."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
REGISTRY = HERE / "lf_ci_control_impact_registry_v2.json"
RUNTIME_CLASSIFIER = HERE / "classify_changed_migration_runtime_v1.py"
RETIRED_CONTROL = "REMOTE_SCHEMA_REPRODUCIBILITY"
RETIRED_CARRIER = "LF_BOOTSTRAP_REPRODUCIBILITY"
RETIRED_WORKFLOW_REL = ".github/workflows/lf-bootstrap-reproducibility.yml"
RETIRED_WORKFLOW = ROOT / RETIRED_WORKFLOW_REL
DB_WORKFLOW = ROOT / ".github/workflows/lf-db-regression.yml"
WORKFLOWS = {
    "LF_CONTRACT_CHECK": ROOT / ".github/workflows/lf-contract-check.yml",
    "VALIDATE_LF_PACKS": ROOT / ".github/workflows/validate-lf-packs.yml",
    "LF_DB_REGRESSION": DB_WORKFLOW,
}


def require(text: str, token: str, code: str) -> None:
    if token not in text:
        raise AssertionError(f"{code}:{token}")


def forbid(text: str, token: str, code: str) -> None:
    if token in text:
        raise AssertionError(f"{code}:{token}")


def require_job_guard(text: str, job_id: str, control_id: str) -> None:
    marker = f"  {job_id}:"
    start = text.find(marker)
    if start < 0:
        raise AssertionError(f"FAIL_CI_CARRIER_JOB_MISSING:{job_id}")
    tail = text[start + len(marker):]
    match = re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", tail)
    end = len(text) if match is None else start + len(marker) + match.start()
    block = text[start:end]
    require(block, "if:", f"FAIL_CI_CARRIER_JOB_UNGUARDED:{job_id}")
    require(block, control_id, f"FAIL_CI_CARRIER_CONTROL_NOT_BOUND:{job_id}")


def assert_registry_retirement(registry: dict) -> None:
    rows = registry["controls"]
    universe = {row["control_id"] for row in rows}
    full = set(registry["full_regression_controls"])

    assert RETIRED_CONTROL not in universe, "FAIL_RETIRED_REMOTE_SCHEMA_CONTROL_IN_REGISTRY"
    assert RETIRED_CONTROL not in full, "FAIL_RETIRED_REMOTE_SCHEMA_CONTROL_IN_FULL_REGRESSION"
    assert all(row["carrier"] != RETIRED_CARRIER for row in rows), "FAIL_RETIRED_BOOTSTRAP_CARRIER_IN_REGISTRY"
    assert all(RETIRED_WORKFLOW_REL not in json.dumps(row, sort_keys=True) for row in rows), "FAIL_RETIRED_BOOTSTRAP_ROUTING_IN_REGISTRY"

    by_id = {row["control_id"]: row for row in rows}
    assert by_id["DB_CANDIDATE_APPLY_ROLLBACK"]["carrier"] == "LF_DB_REGRESSION"
    assert by_id["POLICY_RESOLVER_REGRESSION"]["carrier"] == "LF_DB_REGRESSION"
    assert by_id["V7_RUNTIME_REGRESSION"]["carrier"] == "LF_DB_REGRESSION"
    assert "DB_CANDIDATE_APPLY_ROLLBACK" not in full
    assert "POLICY_RESOLVER_REGRESSION" not in full
    assert "V7_RUNTIME_REGRESSION" in full


def assert_carrier_wiring(texts: dict[str, str]) -> None:
    for carrier, text in texts.items():
        require(text, "lf_ci_execution_plan_v2.py" if carrier == "LF_CONTRACT_CHECK" else "emit_ci_execution_plan_v2.py", f"FAIL_PLAN_NOT_WIRED:{carrier}")

    db = texts["LF_DB_REGRESSION"]
    require(db, "name: LF DB Regression", "FAIL_DB_REGRESSION_NAME")
    require(db, "db_regression_controls_json", "FAIL_DB_REGRESSION_CONTROLS_OUTPUT_MISSING")
    require_job_guard(db, "v7-runtime-apply-rollback", "V7_RUNTIME_REGRESSION")
    require_job_guard(db, "candidate-migration-apply-rollback", "DB_CANDIDATE_APPLY_ROLLBACK")
    require(db, "policy_resolver_post_apply_probe_v1.sql", "FAIL_POLICY_RESOLVER_POST_APPLY_NOT_WIRED")
    require(db, "run_changed_migrations_rollback_v1.py", "FAIL_EXACT_CANDIDATE_ROLLBACK_NOT_WIRED")
    require(db, "ledger_before.txt", "FAIL_CANDIDATE_LEDGER_PRESTATE_MISSING")
    require(db, "ledger_after.txt", "FAIL_CANDIDATE_LEDGER_POSTSTATE_MISSING")

    # A negative assertion mentioning the retired identifier is allowed. What is
    # forbidden is an executable job/routing surface for remote reconstruction.
    forbid(db, "schema-bootstrap-probe:", "FAIL_REMOTE_SCHEMA_EXECUTABLE_JOB_REINTRODUCED")
    forbid(db, "supabase db reset", "FAIL_REMOTE_SCHEMA_REBUILD_COMMAND_REINTRODUCED")
    forbid(db, "LF Bootstrap Reproducibility Probe", "FAIL_RETIRED_WORKFLOW_NAME_REINTRODUCED")


def assert_no_stale_receipt_consumer() -> None:
    operational = [
        ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py",
        ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py",
        ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json",
        ROOT / ".github/workflows/lf-contract-check.yml",
        ROOT / ".github/workflows/validate-lf-packs.yml",
        DB_WORKFLOW,
    ]
    for path in operational:
        text = path.read_text(encoding="utf-8")
        # Guards/tests may mention retired identifiers, but no operational surface
        # may expose the legacy output consumed by downstream jobs.
        forbid(text, "bootstrap_controls_json", f"FAIL_STALE_BOOTSTRAP_RECEIPT_CONSUMER:{path}")


def assert_runtime_classifier() -> None:
    source = RUNTIME_CLASSIFIER.read_text(encoding="utf-8")
    require(source, 'CLASSIFICATION_AUTHORITY = "LIVE_LEDGER_VERSION_NAME"', "FAIL_RUNTIME_CLASSIFIER_IDENTITY_AUTHORITY")
    require(source, 'CONTENT_AUTHORITY = "MIGRATION_SOURCE_PARITY"', "FAIL_RUNTIME_CLASSIFIER_CONTENT_AUTHORITY")
    completed = subprocess.run(
        [sys.executable, str(RUNTIME_CLASSIFIER), "self-test"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=20,
    )
    if completed.returncode != 0:
        raise AssertionError("FAIL_RUNTIME_CLASSIFIER_SELFTEST:" + completed.stdout[-1000:])
    require(completed.stdout, "DB_CANDIDATE_RUNTIME_CLASSIFIER_SELFTEST_PASS", "FAIL_RUNTIME_CLASSIFIER_SELFTEST_RECEIPT")


def main() -> None:
    assert not RETIRED_WORKFLOW.exists(), "FAIL_RETIRED_BOOTSTRAP_WORKFLOW_STILL_EXECUTABLE"
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    assert_registry_retirement(registry)
    texts = {name: path.read_text(encoding="utf-8") for name, path in WORKFLOWS.items()}
    assert_carrier_wiring(texts)
    assert_no_stale_receipt_consumer()
    assert_runtime_classifier()

    print("REMOTE_SCHEMA_RETIREMENT_JUDGE_PASS zero_operational_routing=true zero_jobs=true zero_receipt_consumers=true zero_blocking=true")
    print(f"CI_CONTROL_CARRIER_WIRING_V2_PASS controls={len(registry['controls'])} carriers={len(texts)}")


if __name__ == "__main__":
    main()
