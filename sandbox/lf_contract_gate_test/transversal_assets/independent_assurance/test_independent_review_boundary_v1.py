#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
README = HERE / "README.md"
CONTRACT = HERE / "independent_review_boundary_v1.json"
SOURCE = ROOT / "supabase/migrations/20260915035949_s30_independent_strategy_review_operation_v2.sql"


def section(text: str, heading: str, next_heading: str) -> str:
    return text.split(heading, 1)[1].split(next_heading, 1)[0]


def main() -> None:
    readme = README.read_text(encoding="utf-8")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    source = SOURCE.read_text(encoding="utf-8")

    assert contract["inventory_code"] == "INDEPENDENT_ASSURANCE"
    assert contract["semantic_role"] == "INDEPENDENT_REVIEW"
    assert contract["lifecycle_state"] == "SUPERSEDED_BY_V2_FOR_GENERIC_CONSUMPTION"
    assert contract["superseded_by"] == "independent_review_boundary_v2.json"
    assert contract["rename_mode"] == "NO_PARALLEL_CAPABILITY_USE_EXISTING_IDENTITY_UNTIL_GOVERNED_CUTOVER"
    assert contract["no_duplicate_engine"] is True

    execution = contract["canonical_execution"]
    assert execution["scope"] == "STRATEGY_SPECIALIZATION_ONLY"
    assert execution["operation_code"] == "REVISION_INDEPENDIENTE_ESTRATEGIA_LF"
    assert execution["operation_type"] == "INDEPENDENT_REVIEW"
    assert execution["router_action"] == "STRATEGY_INDEPENDENT_REVIEW"
    assert execution["required_step_ids"] == [
        "route_bind",
        "target_currentness",
        "semantic_review",
        "judge_record",
        "reviewer_readback",
        "report_output",
    ]
    assert set(execution["owned_outputs"]) == {"verdict", "review_receipt", "evidence_refs", "next_gate"}

    downstream = contract["downstream_integration"]
    assert downstream["capability_owner"] == "QUALIFICATION_FRAMEWORK"
    assert downstream["function"] == "public.lf_finalize_qualification_independent_review_v1"
    assert downstream["relationship"] == "CONSUMER_HANDOFF_NOT_OWNED_PHYSICAL_ASSET"

    assert "## Superficies canónicas" in readme
    canonical = section(readme, "## Superficies canónicas", "## Integración downstream")
    assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in canonical
    assert "intentionally excluded" in canonical
    assert "QUALIFICATION_FRAMEWORK" in canonical

    integration = section(readme, "## Integración downstream — no ownership", "## Soporte de sujetos")
    assert "public.lf_finalize_qualification_independent_review_v1" in integration
    assert "QUALIFICATION_FRAMEWORK" in integration
    assert "not a canonical physical asset owned by Independent Review" in integration

    # Historical v1 remains the exact Strategy specialization. Generic consumers
    # must use boundary v2 rather than reinterpreting this route as universal.
    assert "'INDEPENDENT_REVIEW','STRATEGY'" in source
    assert "Independent review is evidence-only until canonical finalizer runs." in source
    for step_id in execution["required_step_ids"]:
        assert f"'{step_id}'" in source, f"FAIL_INDEPENDENT_REVIEW_STEP_MISSING:{step_id}"

    assert contract["inventory_owner_name"]["current_state"] == "SUPER_ADMIN"
    assert contract["inventory_owner_name"]["resolved_by_execution"] == "CHATGPT-INDEPENDENT-ASSURANCE-OWNER-CORRECTION-20261002"

    print("INDEPENDENT_REVIEW_BOUNDARY_V1_STRATEGY_SPECIALIZATION=PASS")


if __name__ == "__main__":
    main()
