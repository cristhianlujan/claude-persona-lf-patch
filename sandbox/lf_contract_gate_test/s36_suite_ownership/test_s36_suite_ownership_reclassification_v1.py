#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260926165500_lf_reclassify_s36_suite_ownership_v1.sql"

EXPECTED = {
    "TS-S36-WP3-ASSET-RETIRE-V1": "S29_ASSET_LIFECYCLE_GOVERNANCE",
    "TS-S36-WP3-PROFILE-TRANSITION-V1": "S26_PROFILE_RUNTIME",
    "TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1": "CARD_OPERATIONS",
    "TS-S36-S26-PR-MERGE-BASE-DRIFT-V1": "S26",
}


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lowered = sql.lower()

    assert "S36-ASSURANCE-BOUNDARY-CONTAMINATION-001" in sql
    assert "UPDATE public.lf_test_suites" in sql
    assert "metadata - 'assurance_owner'" in sql
    assert "'legacy_assurance_owner','S36'" in sql
    assert "'canonical_owner',s.metadata->>'source_owner'" in sql
    assert "'ownership_model','DOMAIN_SOURCE_OWNER'" in sql
    assert "'s36_umbrella_status','RETIRED_AS_OWNER_PRESERVED_AS_LINEAGE'" in sql

    for suite_code, owner in EXPECTED.items():
        assert suite_code in sql, f"FAIL_SUITE_NOT_RECLASSIFIED:{suite_code}"
        assert owner in sql, f"FAIL_OWNER_NOT_BOUND:{suite_code}:{owner}"

    # This solution reclassifies ownership only. It must not copy/rename suites,
    # change execution policy/status/module/name, or create another matrix/runner.
    for token in (
        "insert into public.lf_test_suites",
        "delete from public.lf_test_suites",
        "set status",
        "set module_code",
        "set name",
        "set execution_policy",
        "create table",
        "create or replace function",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_SUITE_RECLASSIFICATION_SCOPE_EXPANSION:{token}"

    assert "LF_S36_SUITE_OWNERSHIP_PRESTATE_MISMATCH" in sql
    assert "LF_S36_SUITE_OWNERSHIP_POSTSTATE_MISMATCH" in sql

    print("S36_SUITE_OWNERSHIP_RECLASSIFICATION=PASS")


if __name__ == "__main__":
    main()
