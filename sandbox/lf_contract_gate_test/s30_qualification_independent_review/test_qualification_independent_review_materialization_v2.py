#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260915025908_s36_qualification_independent_review_materialization_v2.sql"


def main() -> None:
    assert MIGRATION.exists(), "FAIL_QUAL_REVIEW_MATERIALIZATION_SOURCE_MISSING"
    sql = MIGRATION.read_text(encoding="utf-8")

    # Reviewer independence + exact currentness/fingerprint are qualification
    # finalization preconditions, not operation-test-coverage responsibilities.
    assert "q.created_by_execution_id is not distinct from p_reviewer_execution_id" in sql
    assert "QUAL_REVIEW_STALE_REVISION" in sql
    assert "QUAL_REVIEW_SUITE_SET_STALE" in sql
    assert "jr.metadata->>'recorder'='lf_record_test_judge_result_v1'" in sql
    assert "jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id" in sql

    # Qualification finalization materializes strict independent PASS into the
    # canonical test/suite state before the qualification can pass.
    assert "update public.lf_test_runs tr" in sql
    assert "set status='PASS'" in sql
    assert "update public.lf_test_suite_runs sr" in sql
    assert "when a.tests_total>0 and a.tests_passed=a.tests_total then 'PASSED'" in sql
    assert "sr.status is distinct from 'PASSED'" in sql
    assert "'all_required_suites_passed',true" in sql

    # Atomic fail-closed guards prevent partial materialization.
    assert "sr.status not in ('PASSED','REVIEW_REQUIRED')" in sql
    assert "QUAL_REVIEW_PREMATERIALIZATION_SUITE_STATE_INVALID" in sql
    assert "LF_QUAL_REVIEW_MATERIALIZATION_COUNT_MISMATCH" in sql
    assert "LF_QUAL_REVIEW_POSTMATERIALIZATION_INVARIANT_FAILED" in sql

    # Keep materialization behind the canonical finalizer rather than exposing
    # a bypass helper callable independently.
    assert "create or replace function public.lf_materialize_qualification_independent_review_v1" not in sql

    print("QUALIFICATION_INDEPENDENT_REVIEW_MATERIALIZATION_SELFTEST=PASS")


if __name__ == "__main__":
    main()
