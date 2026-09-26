#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260926162000_lf_independent_strategy_review_finalizer_result_contract_fix_v1.sql"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")

    assert "INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001" in sql
    assert "LF_INDEPENDENT_REVIEW_RESULT_FIX_EXPECTED_OLD_WRAPPER_CONTRACT_MISSING" in sql
    assert "LF_INDEPENDENT_REVIEW_RESULT_FIX_FINALIZER_SUCCESS_CONTRACT_MISSING" in sql

    # The deployed qualification finalizer returns this exact success value.
    assert "QUALIFIED_WITH_INDEPENDENT_REVIEW" in sql

    # Compatibility preserves the historical alias but currentness must be
    # enforced for either successful result.
    assert "r->>'result' IN ('QUALIFIED','QUALIFIED_WITH_INDEPENDENT_REVIEW') AND NOT current_ok" in sql
    assert "LF_INDEPENDENT_STRATEGY_REVIEW_FINALIZER_CURRENTNESS_FAILED" in sql
    assert "public.lf_qualification_current_v1('STRATEGY',x.target_code,rev)" in sql

    # Keep the repair bounded: no new table, route, operation or runtime owner.
    lowered = sql.lower()
    for token in (
        "create table",
        "alter table",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
        "runtime_activation",
        "production_activation",
    ):
        assert token not in lowered, f"FAIL_RESULT_CONTRACT_FIX_SCOPE_EXPANSION:{token}"

    assert sql.count("CREATE OR REPLACE FUNCTION public.lf_independent_strategy_review_finalize_v1") == 1
    assert "CREATE OR REPLACE FUNCTION public.lf_finalize_qualification_independent_review_v1" not in sql

    print("INDEPENDENT_REVIEW_FINALIZER_RESULT_CONTRACT_FIX_SELFTEST=PASS")


if __name__ == "__main__":
    main()
