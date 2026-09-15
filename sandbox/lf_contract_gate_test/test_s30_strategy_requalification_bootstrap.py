from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL = (ROOT / 'supabase/migrations/20260915103436_s30_strategy_requalification_bootstrap_v1.sql').read_text(encoding='utf-8').lower()

assert 'lf_strategy_requalification_bootstrap_v1' in SQL
assert "'ejecucion_estrategia_lf'" in SQL
assert 'lf_router_resolve_v1' in SQL
assert 'fn_lf_operation_reserve_execution_v1' in SQL
assert 'lf_record_operation_step_core_v1' in SQL
assert 'lf_run_strategy_qualification_v1' in SQL
assert 'lf_qualification_current_v1' in SQL
assert 'lf_operation_execution_qualification_guard_v1' in SQL
assert 'qualification_bootstrap_only' in SQL
assert 'strategy_requalification_bootstrap_only' in SQL
assert "status='completed'" in SQL
assert 'independent_qualification_review' in SQL
assert "runtime_activation',false" in SQL
assert "production_activation',false" in SQL
assert "scheduler_activation',false" in SQL
assert "orchestrator_activation',false" in SQL
assert 'direct_business_write_allowed' in SQL

# The bootstrap must never mutate Strategy content/state directly.
for forbidden in (
    'update public.lf_strategy_snapshots',
    'insert into public.lf_strategy_snapshots',
    'delete from public.lf_strategy_snapshots',
):
    assert forbidden not in SQL

# It must not weaken or replace the normal executor begin function.
assert 'create or replace function public.lf_strategy_execution_begin_v1' not in SQL
assert 'disable trigger' not in SQL
assert 'session_replication_role' not in SQL

print('S30_STRATEGY_REQUALIFICATION_BOOTSTRAP_SELFTEST=PASS')
