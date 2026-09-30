#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "operation_test_coverage_contract_v1.json"
PROJECTION = HERE / "operation_test_coverage_projection_v1.py"
LEGACY_SOURCE = ROOT / "supabase/migrations/20260914205435_s36_assurance_completeness_engine_v1.sql"


def require(text: str, token: str) -> None:
    assert token in text, f"MISSING_REQUIRED_TOKEN:{token}"


def forbid(text: str, token: str) -> None:
    assert token not in text, f"FOREIGN_RESPONSIBILITY_PRESENT:{token}"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    source = LEGACY_SOURCE.read_text(encoding="utf-8")
    projection = PROJECTION.read_text(encoding="utf-8")
    lowered = source.lower()

    assert contract["schema_version"] == "lf-operation-test-coverage-owner/v1"
    assert contract["capability_code"] == "OPERATION_TEST_COVERAGE"
    assert contract["status"] == "CANDIDATE_TYPED_PROJECTION"
    assert contract["live_cutover_performed"] is False
    assert contract["parallel_test_matrix_allowed"] is False
    assert contract["legacy_state_semantics"]["COVERED"] == "STRUCTURALLY_COVERED"

    typed = contract["typed_projection"]
    assert typed["implementation"] == "operation_test_coverage_projection_v1.py"
    assert typed["material_pass_value"] is False
    assert typed["verdict_state"] == "NOT_EVALUATED"
    assert contract["closure_dependency"]["legacy_pass_aggregate_still_exists"] is True
    assert contract["closure_dependency"]["owner"] == "TEST_COVERAGE_DEBT_GUARD"

    required_owns = {
        "OPERATION_TEST_BINDING_COVERAGE",
        "OPERATION_TEST_SUITE_PRESENCE",
        "OPERATION_TEST_CASE_PRESENCE",
        "UNMAPPED_TEST_RUN_DIAGNOSTIC",
    }
    assert set(contract["owns"]) == required_owns

    required_foreign = {
        "CHANGESET_APPLICABILITY",
        "TEST_EXECUTION",
        "QUALITY_VERDICT",
        "INDEPENDENT_REVIEW",
        "QUALIFICATION_FRAMEWORK",
        "QUALIFICATION_LIFECYCLE_MUTATION",
        "TEST_OR_SUITE_RESULT_MATERIALIZATION",
        "CARD_PREPROMOTION_E2E",
        "ASSET_LIFECYCLE_STATEFUL_ASSURANCE",
        "ADVERSARIAL_AUTHORITY_ASSURANCE",
        "GLOBAL_COVERAGE_DEBT_MONOTONICITY",
        "FULL_REGRESSION",
        "RUNTIME_OR_PRODUCTION_ACTIVATION",
    }
    assert set(contract["does_not_own"]) == required_foreign
    assert contract["related_owners"]["qualification_materialization"] == "QUALIFICATION_FRAMEWORK"
    assert contract["forbidden_new_owner_names"] == ["QUALIFICATION_FINALIZATION"]

    invariants = set(contract["semantic_invariants"])
    for invariant in (
        "QUALIFICATION_OWNER_IS_EXISTING_QUALIFICATION_FRAMEWORK",
        "ZERO_OBSERVED_RUNS_MAY_STILL_BE_STRUCTURALLY_COVERED",
        "STRUCTURAL_COVERAGE_NEVER_IMPLIES_TEST_PASS",
        "STRUCTURAL_COVERAGE_NEVER_IMPLIES_ASSURANCE_PASS",
        "OBSERVED_RUNS_NEVER_CREATE_A_VERDICT_IN_THIS_OWNER",
        "PASS_IS_NOT_A_VALID_STRUCTURAL_COVERAGE_STATE",
        "MATERIAL_PASS_CLAIM_IS_ALWAYS_FALSE",
    ):
        assert invariant in invariants

    for token in (
        "create or replace function public.lf_s36_operation_assurance_coverage_v1()",
        "public.lf_operation_registry",
        "public.lf_test_requirement_bindings",
        "public.lf_test_suites",
        "public.lf_test_suite_cases",
        "public.lf_test_runs",
        "observed_run_count",
        "coverage_state",
    ):
        require(lowered, token.lower())

    for token in (
        "lf_qualification_receipts",
        "lf_finalize_qualification_independent_review_v1",
        "lf_independent_strategy_review",
        "lf_card_update_controlled_assurance",
        "lf_s36_wp3_asset_lifecycle_probe_v1",
        "lf_assurance_claim_catalog",
        "lf_assurance_obligation_catalog",
        "lf_assurance_defeater_catalog",
    ):
        forbid(lowered, token.lower())

    assert "insert into public." not in lowered
    assert "update public." not in lowered
    assert "delete from public." not in lowered

    require(projection, '"STRUCTURALLY_COVERED"')
    require(projection, '"NO_EXECUTION_OBSERVED"')
    require(projection, '"NOT_EVALUATED"')
    require(projection, '"material_pass_claimed": False')
    for token in (
        '"quality_verdict_state": "PASS"',
        '"assurance_verdict_state": "PASS"',
        '"qualification_verdict_state": "PASS"',
        '"material_pass_claimed": True',
    ):
        assert token not in projection, f"MATERIAL_PASS_ASSIGNMENT_PRESENT:{token}"

    print("OPERATION_TEST_COVERAGE_BOUNDARY_PASS owner=OPERATION_TEST_COVERAGE typed_projection=true live_cutover=false")


if __name__ == "__main__":
    main()
