#!/usr/bin/env python3
"""Structural assurance that one CI plan governs all three required carriers."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
REGISTRY = HERE / "lf_ci_control_impact_registry_v2.json"
WORKFLOWS = {
    "LF_CONTRACT_CHECK": ROOT / ".github/workflows/lf-contract-check.yml",
    "VALIDATE_LF_PACKS": ROOT / ".github/workflows/validate-lf-packs.yml",
    "LF_BOOTSTRAP_REPRODUCIBILITY": ROOT / ".github/workflows/lf-bootstrap-reproducibility.yml",
}


def require(text: str, token: str, code: str) -> None:
    if token not in text:
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
    assert start >= 0, f"FAIL_CI_CARRIER_JOB_MISSING:{job_id}"
    match = re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*$", text[start + len(marker):])
    end = start + len(marker) + match.start() if match else len(text)
    block = text[start:end]
    require(block, "if:", f"FAIL_CI_CARRIER_JOB_UNGUARDED:{job_id}")
    require(block, control_id, f"FAIL_CI_CARRIER_CONTROL_NOT_BOUND:{job_id}")

def main() -> None:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    controls = registry["controls"]
    universe = {row["control_id"] for row in controls}
    assert universe, "FAIL_CI_CARRIER_EMPTY_UNIVERSE"
    assert len(universe) == len(controls), "FAIL_CI_CARRIER_DUPLICATE_CONTROL"

    texts = {name:path.read_text(encoding="utf-8") for name,path in WORKFLOWS.items()}

    # All carriers consume the same canonical plan implementation, not a local
    # FAST/DEEP classifier.
    require(texts["LF_CONTRACT_CHECK"], "lf_ci_execution_plan_v2.py", "FAIL_CONTRACT_PLAN_NOT_WIRED")
    require(texts["LF_CONTRACT_CHECK"], "source_ref=exact_head", "FAIL_CONTRACT_EXACT_HEAD_MATERIAL_BINDING_MISSING")
    require(texts["LF_CONTRACT_CHECK"], '["git","diff","--name-only","--no-renames",exact_base,exact_head]', "FAIL_CONTRACT_EXACT_BASE_HEAD_DIFF_MISSING")
    require(texts["LF_CONTRACT_CHECK"], "lf_ci_currentness_bridge_v1.py", "FAIL_CONTRACT_CURRENTNESS_AUTHORITY_NOT_WIRED")
    require(texts["LF_CONTRACT_CHECK"], "refs/heads/main:refs/remotes/origin/main", "FAIL_CONTRACT_MOVING_MAIN_NOT_RESOLVED")
    require(texts["LF_CONTRACT_CHECK"], "applicability_sha256", "FAIL_CONTRACT_APPLICABILITY_SHA_MISSING")
    require(texts["LF_CONTRACT_CHECK"], "evidence_sha256", "FAIL_CONTRACT_EVIDENCE_SHA_MISSING")
    require(texts["LF_CONTRACT_CHECK"], '["git","merge-base",exact_head,authority_current]', "FAIL_CONTRACT_FEATURE_BRANCH_AUTHORITY_BASE_MISSING")
    require(texts["VALIDATE_LF_PACKS"], "emit_ci_execution_plan_v2.py", "FAIL_PACKS_PLAN_NOT_WIRED")
    require(texts["VALIDATE_LF_PACKS"], "refs/heads/main:refs/remotes/origin/main", "FAIL_PACKS_MOVING_MAIN_NOT_RESOLVED")
    require(texts["VALIDATE_LF_PACKS"], "--authority-bound-revision", "FAIL_PACKS_AUTHORITY_BOUND_ARGUMENT_MISSING")
    require(texts["VALIDATE_LF_PACKS"], "--authority-current-revision", "FAIL_PACKS_CURRENTNESS_ARGUMENT_MISSING")
    require(texts["VALIDATE_LF_PACKS"], 'git merge-base "$head" "$authority_current"', "FAIL_PACKS_FEATURE_BRANCH_AUTHORITY_BASE_MISSING")
    require(texts["LF_BOOTSTRAP_REPRODUCIBILITY"], "emit_ci_execution_plan_v2.py", "FAIL_BOOTSTRAP_PLAN_NOT_WIRED")
    require(texts["LF_BOOTSTRAP_REPRODUCIBILITY"], "refs/heads/main:refs/remotes/origin/main", "FAIL_BOOTSTRAP_MOVING_MAIN_NOT_RESOLVED")
    require(texts["LF_BOOTSTRAP_REPRODUCIBILITY"], "--authority-bound-revision", "FAIL_BOOTSTRAP_AUTHORITY_BOUND_ARGUMENT_MISSING")
    require(texts["LF_BOOTSTRAP_REPRODUCIBILITY"], "--authority-current-revision", "FAIL_BOOTSTRAP_CURRENTNESS_ARGUMENT_MISSING")
    require(texts["LF_BOOTSTRAP_REPRODUCIBILITY"], 'git merge-base "$head" "$authority_current"', "FAIL_BOOTSTRAP_FEATURE_BRANCH_AUTHORITY_BASE_MISSING")

    bootstrap = texts["LF_BOOTSTRAP_REPRODUCIBILITY"]
    for forbidden in ("docs_only=", "schema_sensitive=", "deep_required", "remote_schema_required"):
        assert forbidden not in bootstrap, f"FAIL_BOOTSTRAP_PARALLEL_CLASSIFIER_REMAINS:{forbidden}"
    require_job_guard(bootstrap, "schema-bootstrap-probe", "REMOTE_SCHEMA_REPRODUCIBILITY")
    require_job_guard(bootstrap, "v7-runtime-apply-rollback", "V7_RUNTIME_REGRESSION")
    require_job_guard(bootstrap, "candidate-migration-apply-rollback", "DB_CANDIDATE_APPLY_ROLLBACK")
    require(bootstrap, "run_changed_migrations_rollback_v1.py", "FAIL_EXACT_CANDIDATE_ROLLBACK_NOT_WIRED")
    require(bootstrap, "policy_resolver_post_apply_probe_v1.sql", "FAIL_POLICY_RESOLVER_POST_APPLY_NOT_WIRED")
    require(bootstrap, "ledger_before.txt", "FAIL_CANDIDATE_LEDGER_PRESTATE_MISSING")
    require(bootstrap, "ledger_after.txt", "FAIL_CANDIDATE_LEDGER_POSTSTATE_MISSING")

    contract = texts["LF_CONTRACT_CHECK"]
    contract_steps = {
        "Run CI lane router self-tests with deterministic diagnostics": "CI_ROUTER_SELFTEST",
        "Validate declared governance paths": "DECLARED_GOVERNANCE_PATHS",
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

    # Protected S30 self-governance remains an invariant prerequisite. Its owner
    # contract intentionally performs its own guarded applicability and must not
    # be rewritten by this S28 authority repair.
    require(packs, "- name: S30 self-governance regression and fresh receipt gate", "FAIL_S30_INVARIANT_PREREQUISITE_MISSING")
    s30_start = packs.index("- name: S30 self-governance regression and fresh receipt gate")
    s30_end = packs.index("\n      - name:", s30_start + 1)
    s30_block = packs[s30_start:s30_end]
    assert "if: contains(fromJSON(steps.ci_plan.outputs.validate_packs_controls_json)" not in s30_block, "FAIL_S30_PROTECTED_BLOCK_REWRITTEN_BY_S28"

    # Every registry carrier must be represented by a concrete binding token.
    # P0 external remains event-bound inside LF_CONTRACT_CORE; its dependency
    # is explicit and the existing entrypoint must retain the external marker.
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

    # Candidate-bound controls are not allowed to masquerade as generic full
    # regression evidence when no candidate material exists.
    full = set(registry["full_regression_controls"])
    for material_only in ("DB_CANDIDATE_APPLY_ROLLBACK","POLICY_RESOLVER_REGRESSION","P0_FAST_DOCS","P0_EXACT_HEAD_EXTERNAL"):
        assert material_only not in full, f"FAIL_MATERIAL_ONLY_IN_FULL_REGRESSION:{material_only}"

    print(f"CI_CONTROL_CARRIER_WIRING_V2_PASS controls={len(controls)} carriers={len(texts)}")


if __name__ == "__main__":
    main()
