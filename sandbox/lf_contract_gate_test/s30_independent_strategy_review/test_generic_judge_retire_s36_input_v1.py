from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260927001200_lf_test_judge_recorder_retire_s36_input_v1.sql"

sql = MIGRATION.read_text(encoding="utf-8")

assert "('QUALITY_PACK','INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW')" in sql
assert "LF_TEST_JUDGE_RECORDER_S36_PRESTATE" in sql
assert "LF_TEST_JUDGE_RECORDER_S36_STILL_WRITABLE" in sql
assert "The 9 observed historical S36_ASSURANCE rows are lineage/readback evidence only" in sql

for forbidden in [
    "UPDATE public.lf_test_judge_results",
    "DELETE FROM public.lf_test_judge_results",
    "TRUNCATE public.lf_test_judge_results",
    "INSERT INTO public.lf_operation_registry",
    "INSERT INTO public.lf_router_action_registry",
    "CREATE TABLE",
]:
    assert forbidden not in sql, f"scope or historical mutation forbidden: {forbidden}"

print("PASS_GENERIC_JUDGE_S36_INPUT_RETIREMENT checks=10 historical_rewrite=0 parallel_owner=0")
