#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from lf_internal_rpc_acl_analyzer_v1 import analyze

HERE = Path(__file__).resolve().parent


def main() -> int:
    inventory = json.loads((HERE / "live_acl_inventory_20260914.json").read_text(encoding="utf-8"))
    result = analyze(inventory)
    assert result["status"] == "CLIENT_ROLE_EXPOSURE_FOUND"
    assert result["finding_count"] == 4
    names = {x["function"] for x in result["findings"]}
    assert names == {
        "lf_profile_creation_begin_v1",
        "lf_strategy_execution_begin_v1",
        "lf_operation_execution_qualification_guard_v1",
        "lf_apply_independent_strategy_review_v1",
    }
    assert all(x["caller_auth_present"] is False for x in result["findings"])
    assert result["live_apply_allowed"] is False

    safe = {"functions":[{
        "function":"safe","classification":"REFERENCE_SERVICE_ROLE_ONLY","grantees":["postgres","service_role"],
        "checks_auth_uid":False,"checks_jwt":False,"checks_current_user":False,"mutates_data":True
    }]}
    r2 = analyze(safe)
    assert r2["status"] == "NO_UNGOVERNED_CLIENT_EXECUTE_FOUND"
    assert r2["finding_count"] == 0

    sql = (HERE / "internal_rpc_acl_source_candidate_v1.sql").read_text(encoding="utf-8").lower()
    for fn in (
        "lf_profile_creation_begin_v1",
        "lf_strategy_execution_begin_v1",
        "lf_operation_execution_qualification_guard_v1",
        "lf_apply_independent_strategy_review_v1",
    ):
        assert f"revoke execute on function public.{fn}" in sql
        assert f"grant execute on function public.{fn}" in sql
    assert " from public, anon, authenticated" in sql
    assert sql.count(" to service_role;") == 4
    assert "create or replace function" not in sql

    print(json.dumps({"status":"PASS","live_findings":4,"source_privilege_only":True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
