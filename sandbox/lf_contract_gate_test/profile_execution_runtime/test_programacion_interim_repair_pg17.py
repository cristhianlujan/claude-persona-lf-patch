#!/usr/bin/env python3
"""Actual PG17 execution of interim profile selector migration in isolated Docker.

Real original function source, SYNTHETIC catalog/authorization rows, no credentials.
Not a live Router/profile/skill E2E or production receipt.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime"
ORIGINAL = BASE / "lf_programacion_interim_pg17_original_source_v1.sql"
MIGRATION = ROOT / "supabase/migrations/20261109140000_lf_programacion_interim_repair_selection_v1.sql"
CONTAINER = os.environ.get("PG_CONTAINER", "")
BEFORE_MD5 = "de64438021ab995e27cf0494862f5f23"
PROFILE = "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"
REQUEST = "Programa Login B2B con las reglas y politicas aprobadas; no considerar pendientes."


def sql(statement, fail=False):
    if not CONTAINER:
        raise AssertionError("PG_CONTAINER_NOT_CONFIGURED")
    p = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-X", "-A", "-t", "-q",
         "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
        input=statement, text=True, capture_output=True, timeout=70,
    )
    if fail:
        if p.returncode == 0:
            raise AssertionError("EXPECTED_PG_NEGATIVE_FAILURE")
        return p.stderr
    if p.returncode:
        raise AssertionError("PG17_EXECUTION_FAILED:" + p.stderr[-5000:])
    return p.stdout.strip()


def assert_pass(ok, tag):
    if not ok:
        raise AssertionError("FAIL_" + tag)
    print("PASS_" + tag, flush=True)


def select(literal, channel="PROGRAMACION", derivation="NULL::jsonb"):
    lit = literal.replace("'", "''")
    ch = "NULL::text" if channel is None else "'" + channel + "'"
    out = sql(
        "SELECT public.lf_profile_selector_semantic_prepare_v2("
        f"'{lit}',{ch},{derivation},"
        "'{\"alcance\":{\"target_type\":\"PANTALLA\"}}'::jsonb)::text;"
    )
    return json.loads(out)


def codes(result):
    return [x["profile_code"] for x in result["candidate_profiles"]]


def main():
    assert_pass(ORIGINAL.is_file() and MIGRATION.is_file(), "SOURCE_FILES_PRESENT")
    sql(ORIGINAL.read_text(encoding="utf-8"))
    sig = "public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)"
    original_md5 = sql(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure));")
    assert_pass(original_md5 == BEFORE_MD5, "LIVE_FUNCTION_SOURCE_MD5_REPRODUCED")

    before = select(REQUEST)
    assert_pass(codes(before) == ["PERFIL-UI-ARCHITECT"], "BASELINE_PROGRAMMING_ONLY_UI")
    sql(MIGRATION.read_text(encoding="utf-8"))
    after = select(REQUEST)
    assert_pass(codes(after) == [PROFILE], "PROGRAMMING_INITIAL_REPAIR_OWNER")
    assert_pass(after["derivation"] is None and after["effect_authority"] is False
                and after["route_authority"] is False and
                after["downstream_execution_allowed"] is False,
                "NO_ROUTER_EFFECT_OR_DIRECT_AUTHORITY")
    forged = select(REQUEST, derivation="'{\"source_execution_id\":\"EXEC-FORGED\"}'::jsonb")
    assert_pass(forged["derivation"] is None and codes(forged) == [PROFILE],
                "FORGED_DERIVATION_CANNOT_OPEN_ALTERNATE_SELECTION")

    # A legitimately completed DIRECT profile with SAME literal SHA may supply a
    # derivation. It must preserve the original full candidate selection route.
    lit = REQUEST.replace("'", "''")
    sql(
        "INSERT INTO public.lf_operation_execution "
        "(execution_id,operation_code,status,request_sha256,target_code) "
        "VALUES ('EXEC-PROFILE-GATE2-PG17-DERIVED', 'EJECUCION_PERFIL_LF', "
        "'COMPLETED', encode(extensions.digest(convert_to("
        f"'{lit}','UTF8'),'sha256'),'hex'), 'PERFIL-UI-ARCHITECT');"
    )
    derived = select(
        REQUEST,
        derivation="'{\"source_execution_id\":\"EXEC-PROFILE-GATE2-PG17-DERIVED\"}'::jsonb",
    )
    assert_pass(derived["derivation"] == {"source_execution_id":"EXEC-PROFILE-GATE2-PG17-DERIVED"}
                and set(codes(derived)) == {PROFILE, "PERFIL-UI-ARCHITECT"},
                "AUTHENTIC_DERIVED_RETURN_PRESERVES_CATALOG")
    altered = select(
        REQUEST + " altered",
        derivation="'{\"source_execution_id\":\"EXEC-PROFILE-GATE2-PG17-DERIVED\"}'::jsonb",
    )
    assert_pass(altered["derivation"] is None and codes(altered) == [PROFILE],
                "ALTERED_REQUEST_SHA_CANNOT_BYPASS")

    # Replaying the migration after mutation must abort before touching anything.
    err = sql(MIGRATION.read_text(encoding="utf-8"), fail=True)
    assert_pass("LF_PROGRAMACION_SELECTOR_SOURCE_DRIFT" in err,
                "MIGRATION_REPLAY_BLOCKS_ON_SOURCE_DRIFT")
    final = select(REQUEST)
    assert_pass(codes(final) == [PROFILE], "FINAL_READBACK_UNCHANGED_AFTER_REJECTED_REPLAY")
    print(json.dumps({
        "status":"ISOLATED_PG17_PROGRAMMING_SELECTOR_PASS",
        "actual_pg_function_execution": True,
        "live_source_md5_reproduced": True,
        "synthetic_catalog": True,
        "production_writes": False,
        "router_changed": False,
        "profile_run_created": False,
        "skill_invoked": False,
        "negative_replay_verified": True,
    },sort_keys=True),flush=True)


if __name__ == "__main__":
    main()
