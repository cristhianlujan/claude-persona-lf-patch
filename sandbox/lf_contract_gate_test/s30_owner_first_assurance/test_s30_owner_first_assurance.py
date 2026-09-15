#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260915143156_s30_owner_first_post_candidate_assurance_v1.sql"

sql = MIGRATION.read_text(encoding="utf-8")

required = [
    "S30-OWNER-FIRST-POST-CANDIDATE-ASSURANCE-v1",
    "lf_strategy_terminal_qualification_guard_v1",
    "lf_operation_execution_qualification_guard_v1('EJECUCION_ESTRATEGIA_LF'",
    "snapshot_independent_assurance_pre_execution_required',false",
    "snapshot_independent_assurance_timing','POST_CANDIDATE_TERMINAL_EFFECT'",
    "PERFORM public.lf_strategy_terminal_qualification_guard_v1(s.id,'CLOSE_STRATEGY',x.started_at)",
    "LF_STRATEGY_TERMINAL_QUALIFICATION_REQUIRED",
    "owner_execution_pre_assurance_permission_gate_allowed',false",
    "terminal_close_requires_current_qualification',true",
]
for token in required:
    assert token in sql, f"missing required R21 token: {token}"

begin_start = sql.index("CREATE OR REPLACE FUNCTION public.lf_strategy_execution_begin_v1")
begin_end = sql.index("CREATE OR REPLACE FUNCTION public.lf_strategy_lifecycle_from_execution_step_v1", begin_start)
begin_body = sql[begin_start:begin_end]
assert "PERFORM public.lf_strategy_execution_qualification_guard_v1" not in begin_body, "snapshot qualification still pre-gates owner execution"
assert "PERFORM public.lf_operation_execution_qualification_guard_v1" in begin_body, "operation qualification guard was accidentally removed"

lifecycle_start = begin_end
lifecycle_end = sql.index("CREATE OR REPLACE FUNCTION public.lf_strategy_close_write_v1", lifecycle_start)
lifecycle_body = sql[lifecycle_start:lifecycle_end]
assert "lf_strategy_execution_qualification_guard_v1" not in lifecycle_body, "snapshot qualification still pre-gates START_EXECUTION lifecycle transition"

close_start = lifecycle_end
close_end = sql.index("CREATE OR REPLACE FUNCTION public.lf_canary_strategy_unqualified_execution_block_v1", close_start)
close_body = sql[close_start:close_end]
assert "lf_strategy_terminal_qualification_guard_v1" in close_body, "terminal close lost independent qualification boundary"
assert close_body.index("lf_strategy_terminal_qualification_guard_v1") < close_body.index("UPDATE public.lf_strategy_snapshots"), "terminal qualification must execute before Strategy close mutation"

assert "S30_R21_VERIFY_PRE_EXECUTION_QUALIFICATION_GATE_STILL_BOUND" in sql
assert "S30_R21_VERIFY_OPERATION_QUALIFICATION_GUARD_MISSING" in sql
assert "S30_R21_VERIFY_TERMINAL_QUALIFICATION_GATE_MISSING" in sql

print("PASS_S30_R21_OWNER_FIRST_POST_CANDIDATE_ASSURANCE")
