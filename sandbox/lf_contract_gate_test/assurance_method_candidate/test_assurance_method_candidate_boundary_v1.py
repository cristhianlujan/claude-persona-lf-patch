#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CONTRACT = HERE / "assurance_method_candidate_boundary_v1.json"
README = HERE / "README.md"
SOURCE = ROOT / "supabase/migrations/20260916023642_prepare_assurance_method_and_profile_top_tier_v1.sql"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    readme = README.read_text(encoding="utf-8")
    source = SOURCE.read_text(encoding="utf-8")

    assert contract["methodology"] == "LF_ASSURANCE_METHOD_V1"
    assert contract["classification"] == "CANDIDATE_EVALUATION_METHODOLOGY"
    assert contract["pase_control"] is False
    assert contract["critical_path_allowed"] is False
    assert contract["global_activation_allowed"] is False
    assert contract["promotion_mode"] == "SUBJECT_BINDING_SPECIFIC_ONLY"
    assert contract["retirement_required_now"] is False

    counts = contract["observed_live_counts_2026_09_26"]
    assert all(row["active"] == 0 for row in counts.values())
    assert counts["claims"] == {"total": 36, "active": 0, "candidate": 36}
    assert counts["obligations"] == {"total": 48, "active": 0, "candidate": 48}
    assert counts["defeaters"] == {"total": 34, "active": 0, "candidate": 34}
    assert counts["bindings"] == {"total": 4, "active": 0, "candidate": 4}

    consumer = contract["located_candidate_consumer"]
    assert consumer["function"] == "public.lf_eval_strategy_matrix_probe_v1"
    assert consumer["probe"] == "ROUTE_GUARD_CLAIM_SURFACES"
    assert consumer["suite"] == "TS-STRATEGY-OP-EXECUTE-V1"
    assert consumer["suite_status"] == "CANDIDATO"
    assert consumer["case_status"] == "CANDIDATO"

    # The source defines append-only candidate catalogs; it does not establish a PASE carrier.
    assert "LF_ASSURANCE_METHOD_V1" in source
    assert "lf_assurance_claim_catalog" in source
    assert "lf_assurance_obligation_catalog" in source
    assert "lf_assurance_defeater_catalog" in source
    assert "lf_assurance_subject_bindings" in source
    assert "'CANDIDATO'" in source

    for owner in (
        "OPERATION_TEST_COVERAGE",
        "TEST_COVERAGE_DEBT_GUARD",
        "INDEPENDENT_REVIEW",
        "QUALIFICATION_FRAMEWORK",
        "CARD_OPERATIONS",
    ):
        assert owner in contract["domain_ownership_preserved"]

    assert "No global activation by method name." in readme
    assert "candidate evaluation methodology/catalog" in readme
    assert "out of the normal PASE critical path" in readme

    # This package cannot itself materialize or activate the method.
    package = readme + "\n" + CONTRACT.read_text(encoding="utf-8")
    lowered = package.lower()
    for token in (
        "create table",
        "create or replace function",
        "insert into public.lf_assurance_",
        "update public.lf_assurance_",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_ASSURANCE_METHOD_BOUNDARY_ACTIVATES:{token}"

    print("ASSURANCE_METHOD_CANDIDATE_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
