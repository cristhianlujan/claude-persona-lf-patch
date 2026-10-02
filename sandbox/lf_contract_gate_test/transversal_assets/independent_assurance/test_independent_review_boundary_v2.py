#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CONTRACT = HERE / "independent_review_boundary_v2.json"
README = HERE / "README.md"
STORY_CONTRACT = ROOT / "sandbox/lf_contract_gate_test/story_creator_implementation_package/programming_utility_judge_contract_v1.json"
MIGRATION = ROOT / "supabase/migrations/20261002204000_engineering_capability_consumption_closure_guard_v1.sql"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    story = json.loads(STORY_CONTRACT.read_text(encoding="utf-8"))
    readme = README.read_text(encoding="utf-8")
    migration = MIGRATION.read_text(encoding="utf-8")

    assert contract["schema_version"] == "lf-independent-review-boundary/v2"
    assert contract["inventory_code"] == "INDEPENDENT_ASSURANCE"
    assert contract["owner"] == "SUPER_ADMIN"
    assert contract["no_duplicate_engine"] is True
    assert contract["declaration_key"] == "capability_consumption_v1"

    modes = contract["consumption_modes"]
    assert modes["PREFLIGHT_ONLY"]["closure_satisfying"] is False
    assert modes["CLOSURE_REQUIRED"]["closure_satisfying"] is True
    assert set(modes["CLOSURE_REQUIRED"]["required_outputs"]) == {
        "review_receipt",
        "evidence_refs",
        "authority_readback",
    }

    supported = {x["subject_type"]: x for x in contract["supported_subjects_current"]}
    assert supported["STRATEGY"]["status"] == "ACTIVE_SHARED_ENFORCEMENT"
    assert supported["STRATEGY"]["operation_code"] == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
    assert supported["STORY_IMPLEMENTATION_PACKAGE"]["status"] == "PENDING_T_INDEP_EXTENSION"
    assert supported["STORY_IMPLEMENTATION_PACKAGE"]["closure_allowed"] is False
    assert supported["STORY_IMPLEMENTATION_PACKAGE"]["block_code"] == "BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION"

    assert contract["extension"]["owner"] == "SUPER_ADMIN"
    assert contract["extension"]["executor_unit"] == "T-INDEP"
    assert contract["extension"]["executor_work_code"] == "PAULO-035"
    assert contract["extension"]["no_parallel_engine"] is True

    story_consumption = story["capability_consumption"]
    assert story_consumption["mode"] == "CLOSURE_REQUIRED"
    assert story_consumption["binding_resolution"] == "TRANSVERSAL_CONTRACT_AT_EXECUTION"
    assert story_consumption["hardcoded_subject_route_forbidden"] is True
    assert story_consumption["current_subject_support"] == "PENDING_T_INDEP_EXTENSION"
    assert story_consumption["unsupported_subject_result"] == "BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION"
    assert "reviewer_operation" not in story["independence"]
    assert "router_action" not in story["independence"]
    assert story["closure_rule"]["required_checkpoints"] == ["INDEPENDENT_REVIEW_RECEIPT", "AUTHORITY_READBACK"]

    assert "PREFLIGHT_ONLY" in readme and "CLOSURE_REQUIRED" in readme
    assert "BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION" in readme
    assert "T-INDEP / PAULO-035" in readme

    for token in (
        "fn_guard_engineering_capability_closure_v1",
        "capability_consumption_v1",
        "PREFLIGHT_ONLY",
        "CLOSURE_REQUIRED",
        "required_checkpoints",
        "c.status = 'DONE'",
        "c.evidence_ref",
        "CAPABILITY_CLOSURE_REQUIRED_EVIDENCE_MISSING",
    ):
        assert token in migration, f"MISSING_CLOSURE_GUARD_TOKEN:{token}"

    # The guard is capability-neutral: INDEPENDENT_ASSURANCE must not be hardcoded
    # into the migration itself.
    assert "INDEPENDENT_ASSURANCE" not in migration

    print("INDEPENDENT_REVIEW_BOUNDARY_V2=PASS")


if __name__ == "__main__":
    main()
