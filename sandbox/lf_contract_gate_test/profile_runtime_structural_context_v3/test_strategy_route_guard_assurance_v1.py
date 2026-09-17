from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
MIGRATION = REPO / "supabase/migrations/20260917180330_s30_strategy_route_guard_assurance_close_v1.sql"
HELPER = REPO / "sandbox/lf_contract_gate_test/canonical_route_guard/canonical_route_guard.py"


def _load_guard():
    spec = importlib.util.spec_from_file_location("canonical_route_guard_assurance_test", HELPER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_strategy_route_guard_assurance_v1() -> None:
    assert MIGRATION.exists()
    sql = MIGRATION.read_text(encoding="utf-8")
    guard = _load_guard()

    canonical = guard.evaluate_route("EJECUCION_ESTRATEGIA_LF", "EJECUCION_ESTRATEGIA_LF")
    deviation = guard.evaluate_route("EJECUCION_ESTRATEGIA_LF", "GIT_DIRECT")
    exploration = guard.evaluate_route(
        "EJECUCION_ESTRATEGIA_LF", "GIT_DIRECT", explicit_exploration=True
    )
    unresolved = guard.evaluate_route(None, "GIT_DIRECT")

    assert canonical.decision == "PROCEED_CANONICAL"
    assert deviation.decision == "ASK_CANONICAL_OR_EXPLORATORY"
    assert deviation.canonical_effect_allowed is False
    assert exploration.decision == "PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT"
    assert exploration.canonical_effect_allowed is False
    assert unresolved.decision == "RESOLVE_CANONICAL_ROUTE_FIRST"
    assert unresolved.canonical_effect_allowed is False

    required_sql_markers = (
        "lf_canonical_route_guard_classify_v1",
        "lf_strategy_canonical_route_guard_v1",
        "canonical_route_guard_receipt",
        "pre_write_execution_binding_gate",
        "STRATEGY_ROUTER_AUTHENTIC_V1",
        "ROUTE_GUARD_SERVER_BOUND",
        "ROUTE_GUARD_CLASSIFICATION",
        "ROUTE_GUARD_CLAIM_SURFACES",
        "TS-STRATEGY-OP-EXECUTE-V1",
        "c3cdc63b85689ba8c0f69c2f92cb0d2363524d08034483fe6db3764c70be1099",
        "dac89fa8fa022b4fa40ab8a7613e3ef9c444b76e66e19ac2a38ded03cf9d4489",
    )
    for marker in required_sql_markers:
        assert marker in sql, marker

    # No parallel assurance store/engine/matrix is introduced.
    lowered = sql.lower()
    assert "create table" not in lowered
    assert "insert into public.lf_test_suites" not in lowered
    assert "create or replace function public.lf_s36_assurance_completeness" not in lowered

    # Existing canonical suite is enriched rather than duplicated.
    assert sql.count("'TS-STRATEGY-OP-EXECUTE-V1'") >= 7
    for case in ("'E15'", "'E16'", "'E17'", "'E18'", "'E19'", "'E20'"):
        assert case in sql

    # Server-side receipt is derived in the core and not accepted as caller authority.
    assert "v_route_guard:=public.lf_strategy_canonical_route_guard_v1" in sql
    assert (
        "v_payload:=v_payload||jsonb_build_object('canonical_route_guard_receipt',v_route_guard)"
        in sql
    )
    assert "'canonical_route_guard_receipt']::text[]" in sql


if __name__ == "__main__":
    test_strategy_route_guard_assurance_v1()
    print("PASS_STRATEGY_ROUTE_GUARD_ASSURANCE_V1")
