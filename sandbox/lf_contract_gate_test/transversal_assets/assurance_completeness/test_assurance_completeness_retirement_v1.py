#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MIGRATION = ROOT / "supabase/migrations/20260930073000_lf_assurance_completeness_legacy_owner_retirement_v1.sql"
README = Path(__file__).with_name("README.md")


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")
    lowered = sql.lower()
    executable_lowered = "\n".join(
        line for line in lowered.splitlines() if not line.lstrip().startswith("--")
    )

    # Exact currentness and governed source identity.
    for token in (
        "EXEC-ASSURANCE-COMPLETENESS-RETIRE-20260930-001",
        "ASSURANCE_COMPLETENESS_LEGACY_OWNER_RETIREMENT_V1",
        "v1.2-context-admission",
        "9cbea9e36403439303312cd2e1d207c4506356624d224374cbe87220329fcbd5",
        "v1.3-assurance-cutover",
        "REPOSITORY_CI_SET_V1",
        "CI_FAST_DEEP_LANE_ROUTER",
        "REPOSITORY_GOVERNANCE_BUNDLE",
    ):
        assert token in sql, f"RETIREMENT_REQUIRED_TOKEN_MISSING:{token}"

    # The old umbrella is removed from generic context rather than renamed.
    assert "where c.value <> 'ASSURANCE_COMPLETENESS'" in sql
    assert "context_occurrences <> 0" in sql
    assert "policy_payload #> '{context_compilation}'" in sql

    # Inventory currentness is retired but lineage is preserved.
    for token in (
        "estado_documental = 'LEGACY'",
        "estado_operativo = 'READ_ONLY'",
        "RETIRED_LEGACY_LINEAGE",
        "UMBRELLA_OWNER_DECOMPOSED",
        "legacy_function_new_consumer_allowed",
        "OPERATION_TEST_COVERAGE",
        "TEST_COVERAGE_DEBT_GUARD",
        "ASSURANCE_EVALUATOR",
    ):
        assert token in sql, f"RETIREMENT_ASSET_TOKEN_MISSING:{token}"

    # The retirement lot may not activate Assurance by side effect.
    assert "from public.lf_assurance_subject_bindings" in sql
    assert "where status = 'ACTIVE'" in sql
    for forbidden in (
        "update public.lf_assurance_subject_bindings",
        "insert into public.lf_assurance_subject_bindings",
        "delete from public.lf_assurance_subject_bindings",
        "create table",
        "create or replace function",
        "runtime_estado = 'activo'",
        "production",
    ):
        assert forbidden not in executable_lowered, f"RETIREMENT_FORBIDDEN_SIDE_EFFECT:{forbidden}"

    # Source docs cannot advertise the legacy umbrella as consumable.
    assert "LEGACY LINEAGE" in readme
    assert "new consumers: **forbidden**" in readme
    assert "NOT_APPLICABLE_NO_EXECUTION" in readme
    assert "Estado operativo esperado: `ACTIVO`" not in readme
    assert "ACTIVE_SHARED_ENFORCEMENT" not in readme.split("## Readback required for retirement closure")[0]

    print("ASSURANCE_COMPLETENESS_RETIREMENT_V1=PASS generic_context=false legacy_read_only=true active_bindings_unchanged=true")


if __name__ == "__main__":
    main()
