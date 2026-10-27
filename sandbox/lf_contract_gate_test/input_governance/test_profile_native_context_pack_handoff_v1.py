#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"

def _migration() -> str:
    matches = list(MIGRATIONS.glob("*_lf_profile_native_context_pack_runtime_handoff_v1.sql"))
    assert len(matches) == 1, matches
    return matches[0].read_text(encoding="utf-8")


def test_native_bridge_materializes_exact_governed_caller_request():
    sql = _migration()
    for required in (
        "lf_profile_input_governance_runtime_ticket_issue_v1",
        "SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1",
        "input_readiness_context_pack_runtime_v1",
        "X-LF-Profile-Runtime-Ticket",
        "INVOKE_INPUT_GOVERNANCE_CALLER_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE",
        "EJECUCION_PERFIL_LF/input_validate",
        "DIRECT_EDGE_INVOCATION",
    ):
        assert required in sql


def test_native_bridge_keeps_context_pack_queue_and_router_free():
    sql = _migration()
    assert "'queue_required',false" in sql
    assert "'polling_required',false" in sql
    assert "'router_reentry_required',false" in sql
    for forbidden in (
        "fn_input_governance_queue_submit_v1",
        "'STORY_CREATOR'",
        "lf_router_resolve_v1",
        "POSTGRES_SQL_WORKER",
    ):
        assert forbidden not in sql


def test_ticket_is_short_lived_and_not_a_new_profile_execution():
    sql = _migration()
    assert "lf_profile_input_governance_runtime_ticket_issue_v1" in sql
    assert "lf_profile_execution_begin_v1" not in sql
    assert "EJECUCION_PERFIL_LF" in sql
    assert "CREATE TABLE" not in sql
