#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MIGRATION = ROOT / "supabase" / "migrations" / "20261002222500_independent_assurance_subject_extension_v2.sql"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    # Existing engine only.
    assert "operation_code='revision_independiente_estrategia_lf'" in lower
    assert "create or replace function public.lf_independent_review_begin_v2" in lower
    assert "create or replace function public.lf_record_independent_review_step_v2" in lower
    assert "create or replace function public.lf_record_independent_strategy_review_step_v1" in lower

    # Forbidden parallel-stack construction must not appear as writes.
    assert "insert into public.lf_operation_registry" not in lower
    assert "insert into public.lf_router_action_registry" not in lower
    assert "insert into public.lf_operation_judges" not in lower
    assert "values('revision_independiente_lf'" not in lower
    assert "values ('revision_independiente_lf'" not in lower

    # Six existing judge identities are reused, not replaced with Story-specific judges.
    required_judges = {
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1",
    }
    for judge in required_judges:
        assert judge in sql
    assert "STORY_IMPLEMENTATION_PACKAGE" in sql
    assert "EVIDENCE_LEDGER" in sql
    assert "CURRENTNESS_AUTHORITY" in sql
    assert "BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION" in sql
    assert "BUILDER_REVIEWER_NOT_INDEPENDENT" in sql

    # Promotion is deliberately deferred until exact post-migration operation requalification.
    assert "fn_lf_capability_promote_v1(" not in lower
    assert "block_t_indep_premature_current_pointer" in lower
    assert "block_t_indep_expected_requalification_gate_not_observed" in lower

    print("INDEPENDENT_ASSURANCE_SUBJECT_EXTENSION_MIGRATION_V2=PASS")


if __name__ == "__main__":
    main()
