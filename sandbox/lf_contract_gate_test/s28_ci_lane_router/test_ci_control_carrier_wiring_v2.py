#!/usr/bin/env python3
"""Structural assurance for canonical CI carriers, FULL_REGRESSION and Bootstrap retirement."""
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


def require_step_guard(text: str, step_name: str, control_id: str) -> None:
    marker = f"- name: {step_name}"
    start = text.find(marker)
    assert start >= 0, f"FAIL_CI_CARRIER_STEP_MISSING:{step_name}"
    end = text.find("\n      - name:", start + len(marker))
    if end < 0:
        end = len(text)
    block = text[start:end]
    require(block, "if:", f"FAIL_CI_CARRIER_STEP_UNGUARDED:{step_name}")
    require(block, control_id, f"FAIL_CI_CARRIER_CONTROL_NOT_BOUND:{step_name}")


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


def event_block(text: str, event_name: str) -> str:
    lines = text.splitlines()
    marker = f"  {event_name}:"
    for index, line in enumerate(lines):
        if line == marker:
            block = [line]
            for candidate in lines[index + 1 :]:
                if candidate.strip():
                    indent = len(candidate) - len(candidate.lstrip())
                    if indent <= 2:
                        break
                block.append(candidate)
            return "\n".join(block)
    raise AssertionError(f"FAIL_CI_CARRIER_EVENT_MISSING:{event_name}")


def assert_pull_request_admission_parity(texts: dict[str, str]) -> None:
    for carrier, text in texts.items():
        block = event_block(text, "pull_request")
        forbid(block, "branches:", f"FAIL_CI_CARRIER_PR_TARGET_FILTER_PREEMPTS_ROUTER:{carrier}")
        require(block, "ready_for_review", f"FAIL_CI_CARRIER_READY_FOR_REVIEW_EVENT_MISSING:{carrier}")


def assert_registry_retirement(registry: dict) -> None:
    rows = registry["controls"]
    universe = {row["control_id"] for row in rows}
    full = set(registry.get("full_regression_controls") or [])

    assert RETIRED_CONTROL not in universe, "FAIL_RETIRED_REMOTE_SCHEMA_CONTROL_IN_REGISTRY"
    assert RETIRED_CONTROL not in full, "FAIL_RETIRED_REMOTE_SCHEMA_CONTROL_IN_FULL_REGRESSION"
    assert all(row["carrier"] != RETIRED_CARRIER for row in rows), "FAIL_RETIRED_BOOTSTRAP_CARRIER_IN_REGISTRY"
    assert all(RETIRED_WORKFLOW_REL not in json.dumps(row, sort_keys=True) for row in rows), "FAIL_RETIRED_BOOTSTRAP_ROUTING_IN_REGISTRY"

    by_id = {row["control_id"]: row for row in rows}
    assert by_id["DB_CANDIDATE_APPLY_ROLLBACK"]["carrier"] == "LF_DB_REGRESSION"
    assert by_id["POLICY_RESOLVER_REGRESSION"]["carrier"] == "LF_DB_REGRESSION"
    assert by_id["V7_RUNTIME_REGRESSION"]["carrier"] == "LF_DB_REGRESSION"
    if full:
        assert "DB_CANDIDATE_APPLY_ROLLBACK" not in full
        assert "POLICY_RESOLVER_REGRESSION" not in full
        assert "V7_RUNTIME_REGRESSION" in full


def assert_plan_wiring(texts: dict[str, str]) -> None:
    require(texts["LF_CONTRACT_CHECK"], "lf_ci_execution_plan_v2.py", "FAIL_CONTRACT_PLAN_NOT_WIRED")
    require(texts["LF_CONTRACT_CHECK"], "source_ref=exact_head", "FAIL_CONTRACT_EXACT_HEAD_MATERIAL_BINDING_MISSING")
    require(texts["LF_CONTRACT_CHECK"], '["git","diff","--name-only","--no-renames",exact_base,exact_head]', "FAIL_CONTRACT_EXACT_BASE_HEAD_DIFF_MISSING")
    require(texts["LF_CONTRACT_CHECK"], "lf_ci_currentness_bridge_v1.py", "FAIL_CONTRACT_CURRENTNESS_AUTHORITY_NOT_WIRED")
    require(texts["LF_CONTRACT_CHECK"], "refs/heads/main:refs/remotes/origin/main", "FAIL_CONTRACT_MOVING_MAIN_NOT_RESOLVED")
    require(texts["LF_CONTRACT_CHECK"], "applicability_sha256", "FAIL_CONTRACT_APPLICABILITY_SHA_MISSING")
    require(texts["LF_CONTRACT_CHECK"], "evidence_sha256", "FAIL_CONTRACT_EVIDENCE_SHA_MISSING")
    require(texts["LF_CONTRACT_CHECK"], "resolve_authority_evidence_revision", "FAIL_CONTRACT_CURRENTNESS_RESOLVER_NOT_USED")

    require(texts["VALIDATE_LF_PACKS"], "emit_ci_execution_plan_v2.py", "FAIL_PACKS_PLAN_NOT_WIRED")
    require(texts["VALIDATE_LF_PACKS"], "refs/heads/main:refs/remotes/origin/main", "FAIL_PACKS_MOVING_MAIN_NOT_RESOLVED")
    require(texts["VALIDATE_LF_PACKS"], "--authority-current-revision", "FAIL_PACKS_CURRENTNESS_ARGUMENT_MISSING")
    assert "--authority-bound-revision" not in texts["VALIDATE_LF_PACKS"], "FAIL_PACKS_LOCAL_AUTHORITY_BINDING_REMAINS"

    assert_pull_request_admission_parity(texts)

    db = texts["LF_DB_REGRESSION"]
    require(db, "emit_ci_execution_plan_v2.py", "FAIL_DB_REGRESSION_PLAN_NOT_WIRED")
    require(db, "refs/heads/main:refs/remotes/origin/main", "FAIL_DB_REGRESSION_MOVING_MAIN_NOT_RESOLVED")
    require(db, "--authority-current-revision", "FAIL_DB_REGRESSION_CURRENTNESS_ARGUMENT_MISSING")
    assert "--authority-bound-revision" not in db, "FAIL_DB_REGRESSION_LOCAL_AUTHORITY_BINDING_REMAINS"
    require(db, "name: LF DB Regression", "FAIL_DB_REGRESSION_NAME")
    require(db, "db_regression_controls_json", "FAIL_DB_REGRESSION_CONTROLS_OUTPUT_MISSING")
    require_job_guard(db, "v7-runtime-apply-rollback", "V7_RUNTIME_REGRESSION")
    require_job_guard(db, "candidate-migration-apply-rollback", "DB_CANDIDATE_APPLY_ROLLBACK")
    require(db, "run_changed_migrations_rollback_v1.py", "FAIL_EXACT_CANDIDATE_ROLLBACK_NOT_WIRED")
    require(db, "policy_resolver_post_apply_probe_v1.sql", "FAIL_POLICY_RESOLVER_POST_APPLY_NOT_WIRED")
    require(db, "ledger_before.txt", "FAIL_CANDIDATE_LEDGER_PRESTATE_MISSING")
    require(db, "ledger_after.txt", "FAIL_CANDIDATE_LEDGER_POSTSTATE_MISSING")
    require(db, "classify_changed_migration_runtime_v1.py", "FAIL_CANDIDATE_RUNTIME_CLASSIFIER_NOT_WIRED")
    require(db, "emit-query", "FAIL_CANDIDATE_RUNTIME_QUERY_CONTRACT_NOT_WIRED")
    require(db, "classify", "FAIL_CANDIDATE_RUNTIME_CLASSIFY_CONTRACT_NOT_WIRED")

    forbid(db, "schema-bootstrap-probe:", "FAIL_REMOTE_SCHEMA_EXECUTABLE_JOB_REINTRODUCED")
    forbid(db, "supabase db reset", "FAIL_REMOTE_SCHEMA_REBUILD_COMMAND_REINTRODUCED")
    forbid(db, "LF Bootstrap Reproducibility Probe", "FAIL_RETIRED_WORKFLOW_NAME_REINTRODUCED")
    forbid(db, "bootstrap_controls_json", "FAIL_STALE_BOOTSTRAP_RECEIPT_CONSUMER_DB")


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
        forbid(text, "bootstrap_controls_json", f"FAIL_STALE_BOOTSTRAP_RECEIPT_CONSUMER:{path}")


def assert_runtime_classifier() -> None:
    classifier_source = RUNTIME_CLASSIFIER.read_text(encoding="utf-8")
    require(classifier_source, 'CLASSIFICATION_AUTHORITY = "LIVE_LEDGER_VERSION_NAME"', "FAIL_RUNTIME_CLASSIFIER_IDENTITY_AUTHORITY")
    require(classifier_source, 'CONTENT_AUTHORITY = "MIGRATION_SOURCE_PARITY"', "FAIL_RUNTIME_CLASSIFIER_CONTENT_AUTHORITY")
    classifier_test = subprocess.run(
        [sys.executable, str(RUNTIME_CLASSIFIER), "self-test"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=20,
    )
    assert classifier_test.returncode == 0, "FAIL_RUNTIME_CLASSIFIER_SELFTEST:" + classifier_test.stdout[-1000:]
    require(classifier_test.stdout, "DB_CANDIDATE_RUNTIME_CLASSIFIER_SELFTEST_PASS", "FAIL_RUNTIME_CLASSIFIER_SELFTEST_RECEIPT")


def assert_detailed_carrier_guards(texts: dict[str, str], controls: list[dict]) -> None:
    contract = texts["LF_CONTRACT_CHECK"]
    contract_steps = {
        "Run CI lane router self-tests with deterministic diagnostics": "CI_ROUTER_SELFTEST",
        "Enforce declared governance paths through existing gate orchestrator": "DECLARED_GOVERNANCE_PATHS",
        "Verify hosted Supabase Data API excludes net schema": "SUPABASE_CONTROL_PLANE_READBACK",
        "Prepare LF migration source parity frozen inputs": "MIGRATION_SOURCE_PARITY",
        "Enforce required_controls through existing gate orchestrator": "MIGRATION_SOURCE_PARITY",
        "Enforce Input Governance migration source parity": "INPUT_GOVERNANCE_MIGRATION_PARITY",
        "Provision governed P0 visual runtime": "P0_VISUAL_RUNTIME",
        "Run S36 assurance completeness gate self-test with deterministic diagnostics": "S36_ASSURANCE",
        "Enforce S36 assurance completeness debt monotonicity with deterministic diagnostics": "S36_ASSURANCE",
        "Validate LF contract": "LF_CONTRACT_CORE",
        "Run E.16 governance regression matrices with deterministic diagnostics": "E16_GOVERNANCE",
        "Run LF validation engine self-test with deterministic diagnostics": "LF_VALIDATION_ENGINE",
        "Run NO BYPASS judge profile-card-skill self-test with deterministic diagnostics": "NO_BYPASS_PROFILE_CARD_SKILL",
        "Enforce merge and CI evidence for PASS candidates with deterministic diagnostics": "PASS_EVIDENCE",
        "Audit creating-integral-user-stories A01-A62 with deterministic diagnostics": "R8_USER_STORY_AUDIT",
        "Capture authenticated E.16 Actions inventory": "E16_ACTIONS_INVENTORY",
    }
    for step, control in contract_steps.items():
        require_step_guard(contract, step, control)

    packs = texts["VALIDATE_LF_PACKS"]
    checkout_marker = "- name: Checkout repository"
    checkout_start = packs.index(checkout_marker)
    checkout_end = packs.index("\n      - name:", checkout_start + len(checkout_marker))
    checkout_block = packs[checkout_start:checkout_end]
    require(checkout_block, "github.sha", "FAIL_PACKS_PR_MERGE_CHECKOUT_NOT_PRESERVED")
    assert "github.event.pull_request.head.sha" not in checkout_block, "FAIL_PACKS_CHECKOUT_FORCED_TO_CANDIDATE_HEAD"
    require(packs, "LF_PLAN_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}", "FAIL_PACKS_EXACT_HEAD_PLAN_BINDING_MISSING")
    pack_steps = {
        "Validate bounded S30 sandbox regressions": "S30_BOUNDED_REGRESSION",
        "Test persistent Profile Runtime API": "PROFILE_RUNTIME_V3",
        "Validate profile template pack": "PROFILE_PACK",
        "Validate skill template pack": "SKILL_PACK",
        "Validate learning engine pack": "LEARNING_ENGINE_PACK",
        "Validate active transversal README consumption contracts": "TRANSVERSAL_README",
        "Validate transversal grouped gate observability controls": "GATE_CHECK_OBSERVABILITY",
        "Validate PROFILE_RUNTIME V3 decomposed deterministic gates": "PROFILE_RUNTIME_V3",
        "Qualify canonical diagnostic Claim": "GATE_CHECK_OBSERVABILITY",
        "Qualify deep Excel matrix": "GATE_CHECK_OBSERVABILITY",
    }
    for step, control in pack_steps.items():
        require_step_guard(packs, step, control)

    require(packs, "- name: S30 self-governance regression and fresh receipt gate", "FAIL_S30_INVARIANT_PREREQUISITE_MISSING")
    s30_start = packs.index("- name: S30 self-governance regression and fresh receipt gate")
    s30_end = packs.index("\n      - name:", s30_start + 1)
    s30_block = packs[s30_start:s30_end]
    assert "if: contains(fromJSON(steps.ci_plan.outputs.validate_packs_controls_json)" not in s30_block, "FAIL_S30_PROTECTED_BLOCK_REWRITTEN_BY_S28"

    delegated = {"P0_EXACT_HEAD_EXTERNAL"}
    for row in controls:
        cid = row["control_id"]
        carrier = row["carrier"]
        assert carrier in texts, f"FAIL_CI_CARRIER_UNKNOWN:{cid}:{carrier}"
        if cid not in delegated:
            require(texts[carrier], cid, f"FAIL_CI_CARRIER_TOKEN_MISSING:{cid}")
    p0 = next(row for row in controls if row["control_id"] == "P0_EXACT_HEAD_EXTERNAL")
    assert "LF_CONTRACT_CORE" in p0["dependencies"], p0
    entrypoint = (ROOT / "sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py").read_text(encoding="utf-8")
    require(entrypoint, "P0_EXACT_HEAD_EXTERNAL_APPLICABILITY", "FAIL_P0_EXTERNAL_DELEGATED_MARKER_MISSING")


def main() -> None:
    assert not RETIRED_WORKFLOW.exists(), "FAIL_RETIRED_BOOTSTRAP_WORKFLOW_STILL_EXECUTABLE"
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    controls = registry["controls"]
    universe = {row["control_id"] for row in controls}
    assert universe, "FAIL_CI_CARRIER_EMPTY_UNIVERSE"
    assert len(universe) == len(controls), "FAIL_CI_CARRIER_DUPLICATE_CONTROL"

    assert_registry_retirement(registry)
    texts = {name: path.read_text(encoding="utf-8") for name, path in WORKFLOWS.items()}
    assert_plan_wiring(texts)
    assert_no_stale_receipt_consumer()
    assert_runtime_classifier()
    assert_detailed_carrier_guards(texts, controls)

    print("REMOTE_SCHEMA_RETIREMENT_JUDGE_PASS zero_operational_routing=true zero_jobs=true zero_receipt_consumers=true zero_blocking=true")
    print(f"CI_CONTROL_CARRIER_WIRING_V2_PASS controls={len(controls)} carriers={len(texts)}")


if __name__ == "__main__":
    main()
