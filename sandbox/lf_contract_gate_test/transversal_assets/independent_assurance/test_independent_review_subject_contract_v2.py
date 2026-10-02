#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "independent_review_subject_contract_v2.json"


def main() -> None:
    c = json.loads(CONTRACT.read_text(encoding="utf-8"))

    assert c["schema_version"] == "lf-independent-review-subject-contract/v2"
    assert c["capability_code"] == "INDEPENDENT_ASSURANCE"
    assert c["owner_scope"] == "SUPER_ADMIN"
    assert c["extension_class"] == "EXTEND_EXISTING_CAPABILITY"

    execution = c["execution"]
    assert execution["operation_code"] == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
    assert execution["reuse_existing_operation"] is True
    assert execution["reuse_existing_step_judges"] is True
    assert execution["new_operation_allowed"] is False
    assert execution["new_router_action_allowed"] is False
    assert execution["new_judge_engine_allowed"] is False
    assert execution["new_judge_codes_allowed"] is False
    assert execution["new_evidence_store_allowed"] is False

    entry = c["entry"]
    assert "ORCHESTRATOR_EXECUTION_GUARD_V1" in entry["generic_entrypoint"]
    assert "fn_lf_capability_bind_from_orchestrator_v1" in entry["generic_entrypoint"]
    assert entry["consumer_must_not_hardcode_legacy_strategy_route"] is True
    assert entry["legacy_strategy_route_preserved"]["action_code"] == "STRATEGY_INDEPENDENT_REVIEW"

    subjects = c["subject_resolution"]["supported_subjects"]
    assert subjects["STRATEGY"]["path"] == "LEGACY_SPECIALIZATION"
    story = subjects["STORY_IMPLEMENTATION_PACKAGE"]
    assert story["path"] == "GENERIC_SUBJECT_EXTENSION"
    assert story["qualification_handoff"] == "NOT_REQUIRED_FOR_STORY_CLOSURE"
    assert story["subject_authority"] == "EVIDENCE_LEDGER + CURRENTNESS_AUTHORITY"
    assert story["review_receipt_store"] == "EVIDENCE_LEDGER"
    assert set(story["required_dimensions"]) == {
        "implementation_actionability",
        "source_fidelity",
        "reuse_correctness",
        "context_sufficiency",
        "acceptance_executability",
    }

    forbidden = set(c["forbidden"])
    for required in {
        "CREATE_SECOND_INDEPENDENT_REVIEW_OPERATION",
        "CREATE_SECOND_INDEPENDENT_REVIEW_ROUTE",
        "CREATE_PARALLEL_JUDGE_SET",
        "MAP_STORY_IMPLEMENTATION_PACKAGE_TO_STRATEGY",
        "SELF_ISSUE_REVIEW_RECEIPT",
        "STRUCTURAL_PASS_AS_CLOSURE",
    }:
        assert required in forbidden

    print("INDEPENDENT_REVIEW_SUBJECT_CONTRACT_V2=PASS")


if __name__ == "__main__":
    main()
