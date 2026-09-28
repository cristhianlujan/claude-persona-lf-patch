#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "assurance_evaluator_boundary_v1.json"
README = HERE / "README.md"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    readme = README.read_text(encoding="utf-8")

    assert contract["capability_code"] == "ASSURANCE_EVALUATOR"
    assert contract["classification"] == "CANDIDATE_DORMANT_NO_ACTIVE_BINDING"
    assert contract["pase_control_active"] is False
    assert contract["critical_path_allowed_without_active_binding"] is False

    counts = contract["observed_live_counts_2026_09_28"]
    for key in ("claims", "obligations", "defeaters", "bindings"):
        assert counts[key]["active"] == 0, f"unexpected active {key}"
    assert counts["live_evaluator_function_count"] == 0
    assert counts["evaluation_rows"] == 10

    assert contract["normal_pase_without_active_binding"] == "NOT_APPLICABLE_NO_EXECUTION"
    assert contract["unsupported_rule_result"] == "UNPROVEN"
    assert contract["new_review_types"] == ["INDEPENDENT_REVIEW", "INDEPENDENT_HOLDOUT"]
    assert contract["legacy_readback_only"] == ["S36_ASSURANCE"]

    assert contract["ownership"]["applicability_owner"] == "ROUTER_CHANGESET_GOVERNANCE"
    assert contract["ownership"]["finalization_owner"] == "PASE_CLOSURE"
    assert contract["ownership"]["independent_review_owner"] == "INDEPENDENT_REVIEW"
    assert contract["ownership"]["qualification_owner"] == "QUALIFICATION_FRAMEWORK"
    assert contract["reuse"]["evaluation_store"] == "public.lf_assurance_evaluations"

    assert contract["legacy_candidate"]["source_pr"] == 879
    assert contract["legacy_candidate"]["integration_status"] == "SUPERSEDED_AS_PACKAGE"

    # Boundary package is documentation/contract/testing only. It may mention
    # rejected legacy surfaces, but it must not contain executable DB mutations.
    package = (readme + "\n" + CONTRACT.read_text(encoding="utf-8")).lower()
    for token in (
        "create table ",
        "create or replace function ",
        "insert into public.lf_assurance_evaluations",
        "update public.lf_assurance_evaluations",
        "delete from public.lf_assurance_evaluations",
        "insert into public.lf_router_action_registry",
        "insert into public.lf_operation_registry",
    ):
        assert token not in package, f"boundary contains executable activation token: {token}"

    assert "Router / Changeset Governance" in readme
    assert "UNPROVEN" in readme
    assert "NOT_APPLICABLE" in readme

    print("ASSURANCE_EVALUATOR_BOUNDARY=PASS active_bindings=0 live_evaluator=0")


if __name__ == "__main__":
    main()
