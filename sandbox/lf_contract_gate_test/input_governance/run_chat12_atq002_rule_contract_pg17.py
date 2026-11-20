#!/usr/bin/env python3
"""Real ephemeral PostgreSQL17 RULE_CONTRACT_LEVEL test; no remote DB connection."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "sandbox/lf_contract_gate_test/input_governance/fixtures/ig_chat12_atq002_rule_contract_v1.json"
REPORT = ROOT / ".lf_ci/chat12_atq002_pg17/report.json"

def sql_literal(value):
    return "'" + json.dumps(value, ensure_ascii=False, sort_keys=True).replace("'", "''") + "'::jsonb"

def q(sql, expect_fail=False):
    p = subprocess.run(
        ["psql", "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, timeout=30,
        env=os.environ.copy(), check=False,
    )
    if expect_fail:
        if p.returncode == 0:
            raise AssertionError("EXPECTED_REAL_SQL_ERROR_NOT_RAISED")
        return p.stderr
    if p.returncode != 0:
        raise AssertionError("PG17_SQL_FAILED: " + p.stderr[:900])
    return p.stdout.strip()

def require(cond, reason):
    if not cond:
        raise AssertionError(reason)
    return True

def main():
    f = json.loads(FIXTURE.read_text(encoding="utf-8"))
    assert f["rule_code"] == "REG_ATQ_002" and f["test_scope"] == "RULE_CONTRACT_LEVEL_ONLY"
    old = f["source_snapshot_sha256"]
    new = f["candidate_snapshot_sha256"]
    patch = f["governed_rule_patch"]
    changes = patch["changes"]
    g = f["global_config"]
    require(patch["change_kind"] == "FUNCTIONAL", "PATCH_NOT_FUNCTIONAL")
    require(changes["valor_config"] == {"scope": g["scope"], "config_key": g["config_key"]}, "EXACT_REF_REQUIRED")
    require(g["config_value"] == str(f["source_row"]["valor_config"]["max_escaladas_antes_bloqueo"]), "VALUE_DRIFT")
    version_free_description = re.sub(r"lf_auth_config_integer_v[0-9]+", "lf_auth_config_integer_VERSION", changes["descripcion"])
    require(not re.search(r"\d", version_free_description), "DESCRIPTION_NUMERIC_LIMIT_LITERAL")
    checks = {}
    pg = q("SHOW server_version;")
    checks["real_postgresql17"] = require(pg.split(".")[0] == "17", "POSTGRES_NOT_17")
    q("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
    q("CREATE TABLE public.ig_chat12_atq002_probe (payload jsonb NOT NULL); "
      "CREATE TABLE public.ig_chat12_atq002_cfg(scope text,config_key text,config_value text,value_type text,value_status text);")
    q("INSERT INTO public.ig_chat12_atq002_probe VALUES (" + sql_literal(f["source_row"]) + "); "
      "INSERT INTO public.ig_chat12_atq002_cfg VALUES ("
      + ", ".join("'" + g[x].replace("'", "''") + "'" for x in
                  ("scope","config_key","config_value","value_type","value_status")) + ");")
    sha = """encode(digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')"""
    prior = q("SELECT " + sha + " FROM public.ig_chat12_atq002_probe;")
    checks["source_snapshot_sha256"] = require(prior == old, "SOURCE_SHA_MISMATCH")
    checks["single_rule_row_before_after"] = require(q("SELECT count(*) FROM public.ig_chat12_atq002_probe;") == "1", "RULE_ROW_COUNT_CHANGED")
    checks["global_integer_real_value"] = require(
        q("SELECT config_value FROM public.ig_chat12_atq002_cfg "
          "WHERE scope='AUTH' AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK'"
          " AND value_type='INTEGER' AND value_status='REAL';") == g["config_value"],
        "CONFIG_SOURCE_MISSING")
    applied = q("BEGIN; UPDATE public.ig_chat12_atq002_probe SET payload=payload || "
      "jsonb_build_object('descripcion', " + sql_literal(changes["descripcion"]) + ", "
      "'valor_config', " + sql_literal(changes["valor_config"]) + "); "
      "SELECT " + sha + " FROM public.ig_chat12_atq002_probe; ROLLBACK;")
    checks["real_begin_rollback_candidate_sha"] = require(
        new in applied.splitlines(), "CANDIDATE_SHA_MISMATCH")
    after = q("SELECT " + sha + " FROM public.ig_chat12_atq002_probe;")
    checks["independent_connection_readback"] = require(after == old, "ROLLBACK_SOURCE_CHANGED")
    drift = q("BEGIN; UPDATE public.ig_chat12_atq002_probe SET payload="
        "jsonb_set(payload,'{descripcion}',to_jsonb('DRIFT'::text)); SELECT "
        + sha + " FROM public.ig_chat12_atq002_probe; ROLLBACK;")
    checks["negative_source_drift_rejected"] = require(
        old not in drift.splitlines() and len(drift) > 20, "SOURCE_DRIFT_NOT_DETECTED")
    missing = q("BEGIN; DELETE FROM public.ig_chat12_atq002_cfg; DO $gate$ BEGIN "
        "IF NOT EXISTS (SELECT 1 FROM public.ig_chat12_atq002_cfg WHERE "
        "scope='AUTH' AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK' "
        "AND value_type='INTEGER' AND value_status='REAL') THEN "
        "RAISE EXCEPTION 'NO_REAL_CONFIG_FAIL_CLOSED'; END IF; END $gate$;",
        expect_fail=True)
    checks["negative_config_missing_blocks"] = require(
        "NO_REAL_CONFIG_FAIL_CLOSED" in missing, "MISSING_CONFIG_DID_NOT_BLOCK")
    checks["post_negative_readback"] = require(
        q("SELECT " + sha + " FROM public.ig_chat12_atq002_probe;") == old
        and q("SELECT count(*) FROM public.ig_chat12_atq002_cfg;") == "1",
        "NEGATIVE_PROBE_LEFT_EFFECTS")
    checks["original_activation_preserved"] = require(
        "Turnstile invisible falla" in changes["descripcion"]
        and "score supera el umbral de sospecha" in changes["descripcion"]
        and "No se muestra por defecto" in changes["descripcion"],
        "ACTIVATION_SEMANTICS_CHANGED")
    report = {
      "schema_version":"LF_IG_CHAT12_ATQ002_RULE_CONTRACT_PG17_REPORT_V1",
      "status":"PASS" if all(checks.values()) else "FAIL",
      "scope":"RULE_CONTRACT_LEVEL", "backend_e2e":"NOT_TESTED",
      "pg17_real":True, "rollback_real":True, "independent_readback":True,
      "remote_supabase_written":False, "owner_decide_v2":"NOT_CALLED",
      "rule_code":f["rule_code"], "parent_execution_id":f["parent_execution_id"],
      "source_snapshot_sha256":old, "proposal_sha256":f["proposal_sha256"],
      "candidate_snapshot_sha256":new,
      "pg17_version":pg, "checks":checks,
      "preimage":prior,"independent_readback_sha256":after,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(f"IG_CHAT12_ATQ002_PG17_RULE_CONTRACT_{sum(checks.values())}_OF_{len(checks)}_PASS", flush=True)

if __name__ == "__main__":
    main()
