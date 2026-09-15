#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("s36_wp06_ci_completeness_gate.py")
spec = importlib.util.spec_from_file_location("s36_wp06_ci_completeness_gate", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_S36_COMPLETENESS_GATE_LOAD")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert "NEW_REQUIRED_OPERATION_DEBT" in mod.SQL
assert "LIVE_BLOCKED" in mod.SQL
assert "ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE" in mod.SQL
assert "BINDING_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "NEW_RUN_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "lifecycle_state_code = 'OP_OPERATIONAL'" in mod.SQL
assert "assurance_obligation = 'REQUIRED'" in mod.SQL
assert "where id = 61" in mod.SQL
assert "coverage_state <> 'COVERED'" in mod.SQL
assert "x->>'accepted_state'" in mod.SQL
assert "x->>'baseline_required_binding_count'" in mod.SQL
assert "x->>'baseline_observed_run_count'" in mod.SQL
assert "jsonb_array_elements(coalesce(b,'[]'::jsonb))" in mod.SQL
assert "b->'rows'" not in mod.SQL

# S36 qualification independent-review materialization regression.
# A qualification must never become current/QUALIFIED while a required suite remains REVIEW_REQUIRED.
repo_root = Path(__file__).resolve().parents[2]
materialization_migration = repo_root / "supabase/migrations/20260915025908_s36_qualification_independent_review_materialization_v2.sql"
assert materialization_migration.exists(), "FAIL_S36_QUAL_REVIEW_MATERIALIZATION_SOURCE_MISSING"
materialization_sql = materialization_migration.read_text(encoding="utf-8")

# Preserve non-skippable reviewer identity/currentness/fingerprint checks in the only finalizer surface.
assert "q.created_by_execution_id is not distinct from p_reviewer_execution_id" in materialization_sql
assert "QUAL_REVIEW_STALE_REVISION" in materialization_sql
assert "QUAL_REVIEW_SUITE_SET_STALE" in materialization_sql
assert "jr.metadata->>'recorder'='lf_record_test_judge_result_v1'" in materialization_sql
assert "jr.metadata->>'reviewer_execution_id'=p_reviewer_execution_id" in materialization_sql

# Strict PASS judges must be materialized into canonical test/suite state before qualification passes.
assert "update public.lf_test_runs tr" in materialization_sql
assert "set status='PASS'" in materialization_sql
assert "update public.lf_test_suite_runs sr" in materialization_sql
assert "when a.tests_total>0 and a.tests_passed=a.tests_total then 'PASSED'" in materialization_sql
assert "sr.status is distinct from 'PASSED'" in materialization_sql
assert "'all_required_suites_passed',true" in materialization_sql

# Atomic fail-closed guarantees: no partial materialization may survive an invalid suite state,
# row-count mismatch, or unexpected non-PASSED post-state.
assert "sr.status not in ('PASSED','REVIEW_REQUIRED')" in materialization_sql
assert "QUAL_REVIEW_PREMATERIALIZATION_SUITE_STATE_INVALID" in materialization_sql
assert "LF_QUAL_REVIEW_MATERIALIZATION_COUNT_MISMATCH" in materialization_sql
assert "LF_QUAL_REVIEW_POSTMATERIALIZATION_INVARIANT_FAILED" in materialization_sql

# Do not create a separately callable helper that could bypass finalizer checks.
assert "create or replace function public.lf_materialize_qualification_independent_review_v1" not in materialization_sql

print("S36_WP06_COMPLETENESS_GATE_SELFTEST=PASS")
print("S36_QUAL_REVIEW_MATERIALIZATION_SELFTEST=PASS")
