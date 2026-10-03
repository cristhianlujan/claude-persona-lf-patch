#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
README = HERE / "README.md"
CONTRACT = HERE / "independent_review_boundary_v1.json"
SOURCE = ROOT / "supabase/migrations/20260915035949_s30_independent_strategy_review_operation_v2.sql"
MEASURE_SOURCE = ROOT / "supabase/migrations/20261003001000_independent_assurance_oracle_independence_measure_v1.sql"


def section(text: str, heading: str, next_heading: str) -> str:
    return text.split(heading, 1)[1].split(next_heading, 1)[0]


def main() -> None:
    readme = README.read_text(encoding="utf-8")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    source = SOURCE.read_text(encoding="utf-8")
    measure_source = MEASURE_SOURCE.read_text(encoding="utf-8")

    assert contract["inventory_code"] == "INDEPENDENT_ASSURANCE"
    assert contract["semantic_role"] == "INDEPENDENT_REVIEW"
    assert contract["rename_mode"] == "NO_PARALLEL_CAPABILITY_USE_EXISTING_IDENTITY_UNTIL_GOVERNED_CUTOVER"
    assert contract["no_duplicate_engine"] is True
    assert contract["owner_scope"] == "SUPER_ADMIN"
    assert contract["operation_revision_mutation_allowed_by_t_indep"] is False

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

    oracle = contract["oracle_independence"]
    assert oracle["measure_function"] == "public.lf_independent_assurance_measure_v1"
    assert oracle["method"] == "PG_PROC_STATIC_CLOSURE_V1"
    assert oracle["dimensions"] == ["DEPENDENCIES", "DATA", "AUTHOR"]
    assert oracle["dependency_pass_condition"] == "ZERO_UNRESOLVED_SHARED_TRANSITIVE_DEPENDENCIES"
    assert oracle["consumer_unit"] == "M4.4"
    assert oracle["executor_unit"] == "T-INDEP"

    downstream = contract["downstream_integration"]
    assert downstream["capability_owner"] == "QUALIFICATION_FRAMEWORK"
    assert downstream["function"] == "public.lf_finalize_qualification_independent_review_v1"
    assert downstream["relationship"] == "CONSUMER_HANDOFF_NOT_OWNED_PHYSICAL_ASSET"

    assert "## Superficies canónicas" in readme
    canonical = section(readme, "## Superficies canónicas", "## Integración downstream")
    assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in canonical
    assert "public.lf_independent_assurance_measure_v1" in canonical
    assert "intentionally excluded" in canonical
    assert "QUALIFICATION_FRAMEWORK" in canonical

    integration = section(readme, "## Integración downstream — no ownership", "## No responsabilidades")
    assert "public.lf_finalize_qualification_independent_review_v1" in integration
    assert "QUALIFICATION_FRAMEWORK" in integration
    assert "not a canonical physical asset owned by Independent Review" in integration

    criterion = section(readme, "## Criterio de independencia real", "## Cuándo consumirlo")
    for token in ("DEPENDENCY", "DATA", "AUTHOR", "INDEPENDENT", "NOT_INDEPENDENT", "UNPROVEN", "BLOCKED"):
        assert token in criterion, f"FAIL_ORACLE_CRITERION_TOKEN_MISSING:{token}"

    # Historical canonical review lifecycle remains unchanged.
    assert "'INDEPENDENT_REVIEW','STRATEGY'" in source
    assert "Independent review is evidence-only until canonical finalizer runs." in source
    for step_id in execution["required_step_ids"]:
        assert f"'{step_id}'" in source, f"FAIL_INDEPENDENT_REVIEW_STEP_MISSING:{step_id}"

    # T-INDEP adds only a read-only measurement/currentness layer. It must not create
    # another review operation, route or judge stack or mutate canonical operation surfaces.
    lowered_measure = measure_source.lower()
    assert "create or replace function public.lf_independent_assurance_measure_v1" in lowered_measure
    assert "insert into public.lf_operation_registry" not in lowered_measure
    assert "insert into public.lf_router_action_registry" not in lowered_measure
    assert "insert into public.lf_operation_judges" not in lowered_measure
    assert "insert into public.lf_operation_step_contracts" not in lowered_measure
    assert "update public.lf_operation_registry" not in lowered_measure
    assert "update public.lf_operation_contracts" not in lowered_measure
    assert "update public.lf_operation_step_contracts" not in lowered_measure
    assert "update public.lf_operation_judges" not in lowered_measure
    assert "update public.lf_router_action_registry" not in lowered_measure
    assert "lf_operation_revision_sha256_v1('revision_independiente_estrategia_lf')" in lowered_measure
    assert "block_t_indep_canonical_operation_revision_drift" in lowered_measure

    # Capability package itself carries no parallel executable owner.
    package = readme + "\n" + CONTRACT.read_text(encoding="utf-8")
    lowered = package.lower()
    for token in (
        "create table",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_INDEPENDENT_REVIEW_PARALLEL_OWNER:{token}"

    assert contract["inventory_owner_name"]["current_state"] == "RESOLVED_SUPER_ADMIN"
    assert "19472" in contract["inventory_owner_name"]["authority"]

    print("INDEPENDENT_REVIEW_BOUNDARY=PASS")
    print("INDEPENDENT_ASSURANCE_ORACLE_INDEPENDENCE_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
