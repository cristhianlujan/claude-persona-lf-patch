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
    assert contract["rename_mode"] == "NO_PARALLEL_CAPABILITY_USE_EXISTING_IDENTITY_UNTIL_GOVERNED_CUTOVER"
    assert contract["no_duplicate_engine"] is True

    execution = contract["canonical_execution"]
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

    # Preserve the exact heading required by the active transversal README contract.
    assert "## Superficies canónicas" in readme
    canonical = section(readme, "## Superficies canónicas", "## Integración downstream")
    assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in canonical
    # The finalizer may be mentioned only to explicitly exclude it from ownership.
    assert "intentionally excluded" in canonical
    assert "QUALIFICATION_FRAMEWORK" in canonical

    integration = section(readme, "## Integración downstream — no ownership", "## No responsabilidades")
    assert "public.lf_finalize_qualification_independent_review_v1" in integration
    assert "QUALIFICATION_FRAMEWORK" in integration
    assert "not a canonical physical asset owned by Independent Review" in integration

    # Historical source already contains the correct execution boundary: review first,
    # qualification finalization afterwards. Cleanup must preserve that behavior.
    assert "'INDEPENDENT_REVIEW','STRATEGY'" in source
    assert "Independent review is evidence-only until canonical finalizer runs." in source
    for step_id in execution["required_step_ids"]:
        assert f"'{step_id}'" in source, f"FAIL_INDEPENDENT_REVIEW_STEP_MISSING:{step_id}"

    # No parallel owner, route, function or DB object is introduced by this boundary package.
    package = readme + "\n" + CONTRACT.read_text(encoding="utf-8")
    lowered = package.lower()
    for token in (
        "create table",
        "create or replace function",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_INDEPENDENT_REVIEW_PARALLEL_OWNER:{token}"

    assert contract["inventory_owner_name"]["current_state"] == "UNRESOLVED_NULL"
    assert contract["inventory_owner_name"]["repair_rule"] == "AUTHORITATIVE_OWNER_DECISION_REQUIRED_DO_NOT_INFER"

    print("INDEPENDENT_REVIEW_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
