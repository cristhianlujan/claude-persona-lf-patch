#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260926162500_lf_retire_legacy_independent_strategy_review_rpc_v1.sql"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lowered = sql.lower()

    assert "INDEPENDENT-REVIEW-LEGACY-RPC-BYPASS-001" in sql
    assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in sql
    assert "lf_finalize_qualification_independent_review_v1" in sql
    assert "LF_INDEPENDENT_REVIEW_LEGACY_RPC_RETIRED" in sql

    expected_signature = "public.lf_apply_independent_strategy_review_v1(uuid,uuid,uuid,bigint,text,jsonb,text)"
    assert expected_signature in sql
    assert "FROM PUBLIC, anon, authenticated, service_role" in sql

    # The replacement body must be a tombstone, not another mutation engine.
    replacement = sql.split("CREATE OR REPLACE FUNCTION public.lf_apply_independent_strategy_review_v1", 1)[1]
    replacement = replacement.split("REVOKE EXECUTE", 1)[0].lower()
    for token in (
        "update public.lf_test_runs",
        "update public.lf_test_suite_runs",
        "update public.lf_qualification_receipts",
        "insert into",
        "delete from",
        "independent_chat_context",
    ):
        assert token not in replacement, f"FAIL_LEGACY_REVIEW_RPC_STILL_MUTATES:{token}"

    # No new route/operation/table is introduced by retirement.
    for token in (
        "create table",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_LEGACY_REVIEW_RETIREMENT_SCOPE_EXPANSION:{token}"

    print("LEGACY_INDEPENDENT_REVIEW_RPC_RETIREMENT_SELFTEST=PASS")


if __name__ == "__main__":
    main()
