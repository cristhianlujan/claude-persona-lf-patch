#!/usr/bin/env python3
"""M9.3 live, fail-closed evidence acquisition.

Reads the seven current M9.4 governed cohorts from LF sandbox. Executes real
Core, semantic shadow, Curator *plan* and Validator *scope* using PostgreSQL
READ ONLY transactions and independent currentness readbacks. A plan/scope
is NOT a materialized Curator/Validator execution and NEVER counts as a PASS
for the full pipeline. No external runtime invocation, deploy or authoritative
write is performed. A missing capability is a typed blocker, not a simulated
receipt. Designed as a diagnostic input to full_pipeline_candidate.py.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

PROJECT = "mhwmirqcgxxukpctffuv"
COHORTS = {"AUTH", "FORMS", "NAVIGATION", "DESIGN", "ONBOARDING", "RECOVERY", "API"}
STAGES = ("CORE", "SEMANTICS", "CURATOR", "VALIDATOR")
CODE = "ENG_M9_3_LIVE_SHADOW_RUNNER"
DB_NAMES = ("input_readiness_runs", "input_family_assessments")


def digest(v: object) -> str:
    return hashlib.sha256(json.dumps(v, sort_keys=True, ensure_ascii=False,
        separators=(",", ":")).encode()).hexdigest()


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def db_query(sql: str, *, readonly: bool = True) -> object:
    require(bool(shutil.which("psql")), "PSQL_UNAVAILABLE")
    env = os.environ.copy()
    require(env.get("SUPABASE_PROJECT_ID") == PROJECT, "SANDBOX_PROJECT_ID_MISMATCH")
    require(env.get("PGHOST") == "aws-1-us-east-1.pooler.supabase.com",
            "SANDBOX_HOST_MISMATCH")
    require(env.get("PGUSER") == "postgres." + PROJECT,
            "SANDBOX_DB_ROLE_MISMATCH")
    require(bool(env.get("PGPASSWORD")), "DB_PASSWORD_MISSING")
    env["PGSSLMODE"] = "require"
    env["PGDATABASE"] = "postgres"
    transaction = "READ ONLY" if readonly else "READ WRITE"
    script = ("BEGIN TRANSACTION " + transaction +
              "; SET LOCAL statement_timeout = '90000ms';\n" + sql.strip() +
              "\nROLLBACK;\n")
    proc = subprocess.run(["psql", "-X", "--no-psqlrc", "-q", "-A", "-t",
            "--set=ON_ERROR_STOP=1"], input=script, text=True,
            env=env, capture_output=True, timeout=110, check=False)
    if proc.returncode != 0:
        # Never echo connection details or arbitrary database exception payloads.
        raise RuntimeError("SQL_TRANSACTION_FAILED_EXIT_" + str(proc.returncode))
    lines = [x for x in proc.stdout.splitlines() if x.strip()]
    require(len(lines) == 1, "SQL_OUTPUT_NOT_SINGLE_JSON")
    return json.loads(lines[0])


def read_cohorts() -> list[dict]:
    payload = db_query("""SELECT coalesce(jsonb_agg(
        jsonb_build_object('cohort_code',cohort_type_code,
          'screen_id',pantalla_id,'screen_code',screen_code,
          'membership_ref',authority_ref)
        ORDER BY display_order),'[]'::jsonb)
        FROM programacion.v_input_governance_representative_cohort_v1;""")
    require(isinstance(payload, list) and len(payload) == 7,
            "GOVERNED_COHORT_COUNT_NOT_SEVEN")
    require({x.get("cohort_code") for x in payload} == COHORTS,
            "GOVERNED_COHORT_SET_CHANGED")
    require(all(isinstance(x.get("screen_id"), int) and x["screen_id"] > 0
            for x in payload), "INVALID_GOVERNED_SCREEN_ID")
    return payload


def fingerprint() -> dict:
    # Entire authoritative-row corpus, not merely count/max(id); detects edits
    # as well as inserts/deletes. No rows escape into reports.
    return db_query("""SELECT jsonb_build_object(
       'input_readiness_runs',encode(extensions.digest(convert_to(
          coalesce((SELECT string_agg(to_jsonb(r)::text, '|' ORDER BY r.id)
            FROM programacion.input_readiness_runs r),''),'UTF8'),'sha256'),'hex'),
       'input_family_assessments',encode(extensions.digest(convert_to(
          coalesce((SELECT string_agg(to_jsonb(a)::text, '|' ORDER BY a.id)
            FROM programacion.input_family_assessments a),''),'UTF8'),'sha256'),'hex')
     );""")


def capture_one(row: dict) -> dict:
    sid = row["screen_id"]
    sql = f"""SELECT jsonb_build_object(
      'core',programacion.fn_input_screen_canonical_graph({sid},19),
      'semantics',programacion.fn_input_governance_shadow_evaluate_v2({sid},19),
      'curator_plan',programacion.fn_input_governance_curator_plan_v1({sid},false,null),
      'validator_scope',CASE WHEN EXISTS (
          SELECT 1 FROM programacion.input_readiness_runs
          WHERE pantalla_id={sid} AND status='COMPLETED'
        ) THEN programacion.fn_input_validator_semantic_scope_v1(
          (SELECT max(id) FROM programacion.input_readiness_runs
             WHERE pantalla_id={sid} AND status='COMPLETED'))
        ELSE jsonb_build_object('status','NO_COMPLETED_RUN') END
    );"""
    out = dict(row)
    out["vnext_pipeline"] = []
    out["t_equiv"] = {"capability_code": "CONTROL_EQUIVALENCE_JUDGE",
       "status": "BLOCKED", "reason": "FULL_CANDIDATE_AND_BASELINE_NOT_EXECUTED"}
    try:
        result = db_query(sql)
        core, sem = result.get("core"), result.get("semantics")
        out["readback_sha256"] = digest(result)
        out["vnext_pipeline"].append({"stage": "CORE",
            "status": "PASS" if isinstance(core, dict) and core.get("graph_contract") else "BLOCKED",
            "projection_sha256": digest(core)})
        summary = sem.get("summary", {}) if isinstance(sem, dict) else {}
        out["vnext_pipeline"].append({"stage": "SEMANTICS",
            "status": "PASS" if summary.get("family_count") == 47 and
                      sem.get("mutates_readiness") is False else "BLOCKED",
            "summary": summary, "projection_sha256": digest(sem)})
        out["vnext_pipeline"].append({"stage": "CURATOR", "status": "BLOCKED",
            "reason": "CURATOR_PLAN_ONLY_NOT_REAL_MATERIALIZATION",
            "plan_sha256": digest(result.get("curator_plan"))})
        out["vnext_pipeline"].append({"stage": "VALIDATOR", "status": "BLOCKED",
            "reason": "VALIDATOR_SCOPE_ONLY_NOT_REAL_CANDIDATE_VALIDATION",
            "scope_sha256": digest(result.get("validator_scope"))})
    except (RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        out["vnext_pipeline"] = [{"stage": stage, "status": "BLOCKED",
            "reason": "READ_ONLY_CAPTURE_FAILED", "error_type": type(exc).__name__}
            for stage in STAGES]
        out["t_equiv"]["reason"] = "READ_ONLY_CAPTURE_FAILED"
    return out


def run_live(path: Path) -> int:
    captured = dt.datetime.now(dt.timezone.utc).isoformat()
    try:
        cohort_rows = read_cohorts()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('COHORT_AUTHORITY_CAPTURE:' + str(exc)) from exc
    try:
        before = fingerprint()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('PRE_AUTHORITATIVE_SNAPSHOT:' + str(exc)) from exc
    records = [capture_one(x) for x in cohort_rows]
    try:
        after = fingerprint()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('POST_AUTHORITATIVE_SNAPSHOT:' + str(exc)) from exc
    unchanged = before == after
    complete = unchanged and all(
      [s["stage"] for s in x["vnext_pipeline"]] == list(STAGES)
      and all(s["status"] == "PASS" for s in x["vnext_pipeline"])
      and x["t_equiv"]["status"] == "PASS" for x in records)
    # This runner does not and cannot prove actual curator/validator pipeline
    # materialization. It fails closed until a separately qualified, rollback-
    # bounded actual executor produces those receipts.
    require(not complete, "IMPOSSIBLE_FULL_PASS_WITH_DIAGNOSTIC_ONLY_RUNNER")
    payload = {"schema_version": "IG_M9_3_DIAGNOSTIC_CAPTURE_V1",
      "test_code": CODE, "status": "BLOCKED",
      "project_id": PROJECT, "captured_at": captured,
      "runtime_mode": "READ_ONLY_TRANSACTIONS",
      "screen_count": len(records), "cohorts": records,
      "authoritative_readback": {"before": before, "after": after,
                                  "unchanged": unchanged},
      "unmet": ["REAL_CURATOR_CANDIDATE_RECEIPT",
                "REAL_VALIDATOR_CANDIDATE_RECEIPT",
                "5_13_VS_VNEXT_T_EQUIV_PER_COHORT"],
      "test_passed": False, "test_exit_code": 1,
      "semantic_authority_bound": False}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2,
                                 sort_keys=True), encoding="utf-8")
    print(json.dumps({"test_code": CODE, "status": "BLOCKED",
        "screen_count": len(records), "authoritative_readback_unchanged": unchanged,
        "capture_sha256": digest(payload), "evidence_file": str(path),
        "unmet": payload["unmet"]}, sort_keys=True))
    return 1


def self_test() -> int:
    require(COHORTS == {"AUTH","FORMS","NAVIGATION","DESIGN",
                        "ONBOARDING","RECOVERY","API"}, "COHORTS_CHANGED")
    require(len(STAGES) == 4, "STAGE_COUNT_WRONG")
    require(digest({"b": 2, "a": 1}) == digest({"a": 1, "b": 2}),
            "HASH_NOT_CANONICAL")
    try:
        require(False, "NEGATIVE_SHOULD_BLOCK")
    except ValueError as exc:
        require(str(exc) == "NEGATIVE_SHOULD_BLOCK", "NEGATIVE_NOT_TYPED")
    print(json.dumps({"test_code": CODE, "self_test": "PASS",
       "negative": "PASS", "live_pipeline_pass": False}))
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--live", action="store_true")
    p.add_argument("--output", default=".lf_ci/m9_3_live_diagnostic.json")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    require(args.live, "EXPLICIT_LIVE_FLAG_REQUIRED")
    return run_live(Path(args.output))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError) as exc:
        print(json.dumps({"test_code": CODE, "status": "BLOCKED",
            "error_type": type(exc).__name__, "error_code": str(exc),
            "test_exit_code": 1}))
        sys.exit(1)
