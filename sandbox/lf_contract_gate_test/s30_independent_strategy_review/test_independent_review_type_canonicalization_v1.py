from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260926234600_lf_independent_review_type_canonicalization_v1.sql"

sql = MIGRATION.read_text(encoding="utf-8")

required = [
    "p_evidence_payload->>'review_type' IN ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT')",
    "'STRATEGY-QUAL-A03-INDEPENDENT-REVIEW-V1','INDEPENDENT_REVIEW',upper(p_verdict)",
    "'review_type','INDEPENDENT_REVIEW'",
    "if v_review_type not in ('INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW','S36_ASSURANCE') then",
    "QUAL_REVIEW_LEGACY_S36_NOT_PERSISTED",
    "jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW','S36_ASSURANCE')",
    "IF v_count <> 4 THEN",
]
for fragment in required:
    assert fragment in sql, f"missing canonicalization fragment: {fragment}"

# The qualification finalizer has four equivalent historical judge filters. The
# migration must bind that exact observed prestate instead of assuming a count.
assert sql.count("jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')") == 1
assert "Live source has four equivalent judge filters" in sql

# Historical S36 evidence is compatibility input only. This migration must not rewrite it.
for forbidden in [
    "UPDATE public.lf_test_judge_results",
    "DELETE FROM public.lf_test_judge_results",
    "TRUNCATE public.lf_test_judge_results",
]:
    assert forbidden not in sql, f"historical evidence mutation forbidden: {forbidden}"

# The generic judge recorder remains untouched until CARD expertise is canonicalized
# in its own owner lot. Otherwise this PR would break a still-live consumer contract.
assert "to_regprocedure('public.lf_record_test_judge_result_v1" not in sql

# This is a contract/value cutover, not a new engine, route, operation or runtime.
for forbidden in [
    "CREATE TABLE",
    "INSERT INTO public.lf_operation_registry",
    "INSERT INTO public.lf_router_action_registry",
    "runtime_activation",
    "production_activation",
]:
    assert forbidden not in sql, f"scope expansion forbidden: {forbidden}"

print("PASS_INDEPENDENT_REVIEW_TYPE_CANONICALIZATION checks=8 historical_rewrite=0 generic_recorder_change=0")
