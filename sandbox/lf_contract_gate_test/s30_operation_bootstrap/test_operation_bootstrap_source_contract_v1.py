#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    sql = (HERE / "operation_bootstrap_source_candidate_v1.sql").read_text(encoding="utf-8").lower()
    contract = json.loads((HERE / "LF_OPERATION_BOOTSTRAP_CONTRACT_V1.json").read_text(encoding="utf-8"))

    required = [
        "create table if not exists public.lf_operation_bootstrap_policy",
        "bootstrap_mode in ('generic','wrapper_required','disabled')",
        "alter table public.lf_operation_bootstrap_policy enable row level security",
        "create or replace function public.lf_operation_bootstrap_core_v1",
        "create or replace function public.lf_operation_begin_v1",
        "public.fn_lf_operation_reserve_execution_v1",
        "public.lf_operation_execution_qualification_guard_v1",
        "for update",
        "lf_operation_bootstrap_init_step_not_exact",
        "lf_operation_bootstrap_init_binding_not_exact",
        "lf_operation_bootstrap_init_judge_not_exact",
        "lf_operation_bootstrap_execution_already_materialized",
        "lf_operation_bootstrap_readback_failed",
        "revoke all on function public.lf_operation_bootstrap_core_v1",
        "revoke all on function public.lf_operation_begin_v1",
        "grant execute on function public.lf_operation_bootstrap_core_v1",
        "grant execute on function public.lf_operation_begin_v1",
        "to service_role",
        "no policy rows are seeded"
    ]
    missing = [token for token in required if token not in sql]
    assert not missing, missing
    assert "security definer" not in sql
    assert "grant execute" in sql and " to anon" not in sql and " to authenticated" not in sql
    assert "insert into public.lf_operation_bootstrap_policy" not in sql
    assert "update public.lf_operation_execution set status='completed'" not in sql
    assert contract["admission"]["legacy_zero_step_execution"] == "DO_NOT_AUTO_BACKFILL"
    assert contract["security"]["service_role_execute"] is True
    assert contract["security"]["public_execute"] is False

    print(json.dumps({"status":"PASS","source_invariants":23,"live_apply":False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
