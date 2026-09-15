from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"

r15_sources = sorted(MIGRATIONS.glob("*_s30_strategy_update_required_step_sequence_guard_v1.sql"))
assert len(r15_sources) == 1, r15_sources
sql = r15_sources[0].read_text(encoding="utf-8")
low = sql.lower()

assert "lf_strategy_update_required_prewrite_sequence_not_clean" in low
assert "public.lf_operation_steps" in low
assert "public.lf_operation_execution_steps" in low
assert "public.lf_operation_step_judge_bindings" in low
assert "st.required is true" in low
assert "st.active is true" in low
assert "es.status=b.clean_result_value" in low
assert "recorded_by_rpc'='lf_strategy_update_begin_v1" in low
assert "core_recorder'='lf_record_operation_step_core_v1" in low
assert low.index("lf_strategy_update_required_prewrite_sequence_not_clean") < low.index("new_metadata:=")

reg = (ROOT / "sandbox/lf_contract_gate_test/strategy_update/r15_required_prewrite_sequence_regression.sql").read_text(encoding="utf-8")
reg_low = reg.lower()

assert reg_low.lstrip().startswith("-- s30-r15 rollback-only")
assert "begin;" in reg_low and "rollback;" in reg_low
assert "lf_strategy_update_begin_v1" in reg_low
assert "lf_record_operation_step_core_v1" in reg_low
assert "lf_strategy_update_write_v1" in reg_low
assert "prior_required_step_not_clean" in reg_low
assert "init_only=blocked" in reg_low
assert "reorder=blocked" in reg_low
assert "nonclean=blocked" in reg_low
assert "clean_chain=one_bounded_write" in reg_low

for forbidden in (
    "disable trigger",
    "session_replication_role",
    "insert into public.lf_operation_execution_steps",
    "update public.lf_operation_execution_steps",
    "delete from public.lf_operation_execution_steps",
    "update public.lf_strategy_snapshots",
    "insert into public.lf_strategy_snapshots",
    "delete from public.lf_strategy_snapshots",
):
    assert forbidden not in reg_low, forbidden

print("S30_R15_STRATEGY_UPDATE_SEQUENCE_GUARD_SELFTEST=PASS")
