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


def classify_source_delta(before: object, after: object) -> dict:
    """Classify differences between frozen 5.13 and current vNext source
    receipts without silently equating their input snapshots.
    Explicit version-change observations NEVER authorize promotion.
    """
    require(isinstance(before, list) and isinstance(after, list),
            "SOURCE_MANIFEST_PROVENANCE_MISSING")
    def index(rows: list) -> dict:
        out = {}
        for row in rows:
            require(isinstance(row, dict) and isinstance(row.get("ref"), dict),
                    "SOURCE_RECEIPT_MALFORMED")
            key = json.dumps(row["ref"], sort_keys=True, separators=(",", ":"))
            require(key not in out, "DUPLICATE_SOURCE_REFERENCE")
            out[key] = row
        return out
    left, right = index(before), index(after)
    kinds, unknown = set(), set()
    details = []
    recognized = {"CONTRACT", "SCREEN_CANONICAL_GRAPH", "CURRENT_VISUAL_ARTIFACT"}
    for key in sorted(set(left) | set(right)):
        a, b = left.get(key), right.get(key)
        if a is not None and b is not None and a.get("observed_sha256") == b.get("observed_sha256"):
            continue
        ref = (a or b)["ref"]
        kind = ref.get("kind", "UNKNOWN")
        kinds.add(kind)
        if kind not in recognized:
            unknown.add(kind)
        details.append({"kind": kind, "change": "NEW" if a is None
                        else "REMOVED" if b is None else "OBSERVED_HASH_CHANGED",
                        "previous_sha256": a.get("observed_sha256") if a else None,
                        "candidate_sha256": b.get("observed_sha256") if b else None})
    return {"status": "BLOCKED_UNCLASSIFIED_SOURCE_DELTA" if unknown else
              "CLASSIFIED_VERSION_SOURCE_DELTA",
            "change_count": len(details), "changed_kinds": sorted(kinds),
            "unknown_kinds": sorted(unknown), "changed_receipts": details,
            "same_snapshot": len(details) == 0}


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
              "; SET LOCAL statement_timeout = '180000ms';\n" + sql.strip() +
              "\nROLLBACK;\n")
    proc = subprocess.run(["psql", "-X", "--no-psqlrc", "-q", "-A", "-t",
            "--set=ON_ERROR_STOP=1"], input=script, text=True,
            env=env, capture_output=True, timeout=210, check=False)
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



def capture_rollback_one(row: dict) -> dict:
    """Actual curator/validator candidate execution inside one ROLLBACK-only
    sandbox transaction. Independent completed-run baseline is read before
    materialization and may not be fabricated if unavailable."""
    sid = row["screen_id"]
    sql = f"""
      SET LOCAL lock_timeout = '2000ms';
      CREATE TEMP TABLE m93_baseline AS SELECT id,source_snapshot_sha256
        FROM programacion.input_readiness_runs
        WHERE pantalla_id={sid} AND version_id=19 AND status='COMPLETED'
          AND contract_revision='5.13' ORDER BY id DESC LIMIT 1;
      CREATE TEMP TABLE m93_core AS SELECT
        programacion.fn_input_screen_canonical_graph({sid},19) AS j;
      CREATE TEMP TABLE m93_semantics AS SELECT
        programacion.fn_input_governance_shadow_evaluate_v2({sid},19) AS j;
      CREATE TEMP TABLE m93_curator AS SELECT
        programacion.fn_input_governance_curator_materialize_v1(
          {sid},'STORY_CREATOR','INPUT_CURATOR:SQL:ig-governed-dispatch-v1:M93ShadowRollback001',true) AS j;
      CREATE TEMP TABLE m93_validator AS SELECT
        CASE WHEN c.j->>'status'='VALIDATOR_RUNTIME_REQUIRED'
          AND jsonb_typeof(c.j->'run_id')='number'
          AND jsonb_typeof(c.j->'curator_handoff_receipt'->'receipt_id')='number'
        THEN programacion.fn_input_governance_validator_validate_handoff_v1(
          (c.j->>'run_id')::bigint,
          'INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:M93ShadowRollback001',
          (c.j->'curator_handoff_receipt'->>'receipt_id')::bigint)
        ELSE jsonb_build_object('status','M93_REAL_VALIDATOR_HANDOFF_UNAVAILABLE')
        END AS j FROM m93_curator c;
      DO $m93_validator_loop$
      DECLARE v_run_id bigint;
              v_status text;
              v_chunk integer:=0;
              v_payload jsonb;
      BEGIN
        SELECT (j->>'run_id')::bigint INTO v_run_id FROM m93_curator
          WHERE jsonb_typeof(j->'run_id')='number';
        IF v_run_id IS NOT NULL THEN
          LOOP
            SELECT j->>'status' INTO v_status FROM m93_validator;
            EXIT WHEN v_status NOT IN
              ('VALIDATOR_CONTINUE_REQUIRED','VALIDATOR_RESUME_REQUIRED');
            IF v_chunk>=8 THEN
              RAISE EXCEPTION 'M93_VALIDATOR_CONTINUATION_BUDGET_EXCEEDED';
            END IF;
            v_payload:=programacion.fn_input_governance_validator_validate_v1(
              v_run_id,
              'INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:M93ShadowRollback001');
            UPDATE m93_validator SET j=v_payload;
            v_chunk:=v_chunk+1;
          END LOOP;
        END IF;
      END $m93_validator_loop$;
      SELECT jsonb_build_object(
        'baseline_run_id',(SELECT id FROM m93_baseline),
        'baseline_revision','5.13',
        'baseline_manifest',(SELECT r.source_manifest FROM programacion.input_readiness_runs r WHERE r.id=(SELECT id FROM m93_baseline)),
        'candidate_manifest',(SELECT r.source_manifest FROM programacion.input_readiness_runs r WHERE r.id=(SELECT (j->>'run_id')::bigint FROM m93_curator WHERE jsonb_typeof(j->'run_id')='number')),
        'source_snapshot_match',((SELECT source_snapshot_sha256 FROM m93_baseline) IS NOT NULL AND
          (SELECT source_snapshot_sha256 FROM m93_baseline) =
          (SELECT r.source_snapshot_sha256 FROM programacion.input_readiness_runs r
           WHERE r.id=(SELECT (j->>'run_id')::bigint FROM m93_curator
             WHERE jsonb_typeof(j->'run_id')='number'))),
        'core',(SELECT j FROM m93_core),
        'semantics',(SELECT j FROM m93_semantics),
        'curator',(SELECT j FROM m93_curator),
        'validator',(SELECT j FROM m93_validator),
        'validator_chunk_count',(
           SELECT count(*) FROM programacion.input_validator_chunk_timings
           WHERE run_id=(SELECT (j->>'run_id')::bigint FROM m93_curator
               WHERE jsonb_typeof(j->'run_id')='number')),
        'validator_blocked_family_count',(
           SELECT count(*) FROM programacion.input_family_assessments
           WHERE run_id=(SELECT (j->>'run_id')::bigint FROM m93_curator
               WHERE jsonb_typeof(j->'run_id')='number')
             AND validator_outcome='BLOCKED'),
        'baseline',(SELECT coalesce(jsonb_agg(
          jsonb_build_object('family_code',a.family_code,
            'coverage_status',a.coverage_status,
            'well_defined_status',a.well_defined_status,
            'story_ready_status',a.story_ready_status,
            'implementation_ready_status',a.implementation_ready_status,
            'qa_ready_status',a.qa_ready_status,
            'production_ready_status',a.production_ready_status,
            'validator_outcome',a.validator_outcome)
          ORDER BY a.family_code),'[]'::jsonb)
          FROM programacion.input_family_assessments a
          WHERE a.run_id=(SELECT id FROM m93_baseline)),
        'candidate',(SELECT coalesce(jsonb_agg(
          jsonb_build_object('family_code',a.family_code,
            'coverage_status',a.coverage_status,
            'well_defined_status',a.well_defined_status,
            'story_ready_status',a.story_ready_status,
            'implementation_ready_status',a.implementation_ready_status,
            'qa_ready_status',a.qa_ready_status,
            'production_ready_status',a.production_ready_status,
            'validator_outcome',a.validator_outcome)
          ORDER BY a.family_code),'[]'::jsonb)
          FROM programacion.input_family_assessments a
          WHERE a.run_id=(SELECT (j->>'run_id')::bigint
              FROM m93_curator WHERE jsonb_typeof(j->'run_id')='number'))
      );"""
    out = dict(row)
    out["vnext_pipeline"] = []
    out["t_equiv"] = {"capability_code":"CONTROL_EQUIVALENCE_JUDGE",
                      "status":"BLOCKED", "reason":"EXECUTION_NOT_VALIDATED"}
    try:
        result = db_query(sql, readonly=False)
        core, sem = result.get("core"), result.get("semantics")
        curator, validator = result.get("curator"), result.get("validator")
        out["vnext_pipeline"] = [
          {"stage":"CORE","status":"PASS" if isinstance(core,dict) and
            core.get("graph_contract") else "BLOCKED","projection_sha256":digest(core)},
          {"stage":"SEMANTICS","status":"PASS" if isinstance(sem,dict) and
            sem.get("summary",{}).get("family_count")==47 else "BLOCKED",
            "projection_sha256":digest(sem)},
          {"stage":"CURATOR","status":"PASS" if isinstance(curator,dict) and
            curator.get("status")=="VALIDATOR_RUNTIME_REQUIRED" and
            isinstance(curator.get("curator_handoff_receipt"),dict) else "BLOCKED",
            "result_status":curator.get("status") if isinstance(curator,dict) else None,
            "projection_sha256":digest(curator)},
          {"stage":"VALIDATOR","status":"PASS" if isinstance(validator,dict) and
            validator.get("status") in ("COMPLETED","NOOP_COMPLETED") else "BLOCKED",
            "result_status":validator.get("status") if isinstance(validator,dict) else None,
            "projection_sha256":digest(validator)}]
        from importlib.util import spec_from_file_location, module_from_spec
        module_path = (Path(__file__).resolve().parents[2] /
            "transversal_assets/control_equivalence/control_equivalence_judge_v1.py")
        require(module_path.is_file(), "TEQUIV_CANONICAL_PROVIDER_MISSING")
        spec = spec_from_file_location("m93_tequiv",module_path)
        require(spec is not None and spec.loader is not None, "TEQUIV_IMPORT_UNAVAILABLE")
        module=module_from_spec(spec)
        spec.loader.exec_module(module)
        baseline,candidate=result.get("baseline"),result.get("candidate")
        require(isinstance(baseline,list) and isinstance(candidate,list) and
                len(baseline)==47 and len(candidate)==47,
                "TEQUIV_BASELINE_OR_CANDIDATE_NOT_47")
        delta=classify_source_delta(result.get('baseline_manifest'),result.get('candidate_manifest'))
        out['source_delta']=delta
        # The provider owns the comparison mechanics. The M9.3 consumer owns
        # exact per-field D4 meanings: a changed readiness or validator verdict
        # is a BLOCKING semantic hold, not a failed execution of shadow.
        fields=("coverage_status","well_defined_status","story_ready_status",
                "implementation_ready_status","qa_ready_status",
                "production_ready_status","validator_outcome")
        mapping={}
        for i,(old,new) in enumerate(zip(baseline,candidate)):
            require(old.get("family_code")==new.get("family_code"),
                    "TEQUIV_FAMILY_IDENTITY_MISMATCH")
            for field in fields:
                mapping[f"families[{i}].{field}"]={
                  "level":"D4",
                  "meaning":"READINESS_OR_VALIDATOR_VERDICT_CHANGE_REQUIRES_INDEPENDENT_REVIEW",
                  "blocking":True}
        policy={"schema_version":"lf-control-equivalence-policy/v1",
                "consumer_ref":"IG_CURATOR_VALIDATOR_REFACTOR_V2:M9.3",
                "field_levels":mapping}
        eq=module.evaluate({"families":baseline},{"families":candidate},policy)
        eq_status="PASS" if eq.get("result")=="PASS_EQUIVALENT" else (
            "CLASSIFIED_HOLD" if eq.get("result")=="BLOCKED_DIVERGENCE"
            and all(d.get("level")=="D4" and d.get("blocking") is True
                    for d in eq.get("divergences",[]))
            and eq.get("divergence_count",0)>0 else "BLOCKED")
        if delta.get("status")!="CLASSIFIED_VERSION_SOURCE_DELTA":
            eq_status="BLOCKED"
        out["t_equiv"]={
           "capability_code":"CONTROL_EQUIVALENCE_JUDGE",
           "baseline":"5.13","candidate":"VNEXT",
           "status":eq_status,
           "difference_count":eq.get("divergence_count"),
           "result":eq.get("result"),
           "comparison_level":eq.get("comparison_level"),
           "policy_sha256":digest(policy),
           "semantic_hold":eq_status=="CLASSIFIED_HOLD",
           "evidence_sha256":digest(eq)}
        out["validator_chunk_count"]=result.get("validator_chunk_count")
        out["validator_blocked_family_count"]=result.get("validator_blocked_family_count")
        out["baseline_run_id"]=result.get("baseline_run_id")
        out["baseline_revision"]=result.get("baseline_revision")
        out["source_snapshot_match"]=result.get("source_snapshot_match")
        out["comparison_sha256"]=digest({"baseline":baseline,"candidate":candidate})
    except (RuntimeError,ValueError,subprocess.TimeoutExpired) as exc:
        out["vnext_pipeline"]=[{"stage":s,"status":"BLOCKED",
            "reason":"ROLLBACK_EXECUTION_FAILED",
            "error_code":str(exc) if isinstance(exc,(RuntimeError,ValueError))
                else "SQL_TIMEOUT"} for s in STAGES]
        out["t_equiv"]["reason"]="ROLLBACK_EXECUTION_FAILED"
    return out


def run_live(path: Path, *, rollback_e2e: bool = False, cohort: str | None = None) -> int:
    captured = dt.datetime.now(dt.timezone.utc).isoformat()
    try:
        cohort_rows = read_cohorts()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('COHORT_AUTHORITY_CAPTURE:' + str(exc)) from exc
    try:
        before = fingerprint()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('PRE_AUTHORITATIVE_SNAPSHOT:' + str(exc)) from exc
    if cohort is not None:
        require(cohort in COHORTS, 'UNKNOWN_GOVERNED_COHORT')
        cohort_rows = [x for x in cohort_rows if x['cohort_code']==cohort]
    records = [capture_rollback_one(x) if rollback_e2e else capture_one(x)
               for x in cohort_rows]
    try:
        after = fingerprint()
    except (RuntimeError, ValueError) as exc:
        raise RuntimeError('POST_AUTHORITATIVE_SNAPSHOT:' + str(exc)) from exc
    unchanged = before == after
    complete = unchanged and all(
      [s["stage"] for s in x["vnext_pipeline"]] == list(STAGES)
      and all(s["status"] == "PASS" for s in x["vnext_pipeline"])
      and x["t_equiv"]["status"] in ("PASS","CLASSIFIED_HOLD") for x in records)
    # This runner does not and cannot prove actual curator/validator pipeline
    # materialization. It fails closed until a separately qualified, rollback-
    # bounded actual executor produces those receipts.
    if not rollback_e2e:
        require(not complete, 'READ_ONLY_DIAGNOSTIC_CANNOT_PASS')
    if cohort is not None:
        complete = False
    payload = {"schema_version": "IG_M9_3_ROLLBACK_CAPTURE_V1" if rollback_e2e else "IG_M9_3_DIAGNOSTIC_CAPTURE_V1",
      "test_code": CODE, "status": "PASS" if complete else "BLOCKED",
      "project_id": PROJECT, "captured_at": captured,
      "runtime_mode": "ROLLBACK_ONLY_SANDBOX" if rollback_e2e else "READ_ONLY_TRANSACTIONS",
      "screen_count": len(records), "cohorts": records,
      "authoritative_readback": {"before": before, "after": after,
                                  "unchanged": unchanged},
      "unmet": [] if complete else ["FULL_M9_3_SEVEN_COHORTS_NOT_VERIFIED"],
      "shadow_decisional": False,
      "production_authorized": False,
      "promotion_authorized": False,
      "semantic_holds": [x["cohort_code"] for x in records if x["t_equiv"].get("status")=="CLASSIFIED_HOLD"],
      "test_passed": complete, "test_exit_code": 0 if complete else 1,
      "semantic_authority_bound": complete}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2,
                                 sort_keys=True), encoding="utf-8")
    print(json.dumps({"test_code": CODE, "status": "PASS" if complete else "BLOCKED",
        "screen_count": len(records), "authoritative_readback_unchanged": unchanged,
        "capture_sha256": digest(payload), "evidence_file": str(path),
        "unmet": payload["unmet"]}, sort_keys=True))
    return 0 if complete else 1


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
    classified=classify_source_delta(
        [{"ref":{"kind":"CONTRACT"},"observed_sha256":"old"}],
        [{"ref":{"kind":"CONTRACT"},"observed_sha256":"new"}])
    require(classified["status"]=="CLASSIFIED_VERSION_SOURCE_DELTA"
            and classified["change_count"]==1, "KNOWN_SOURCE_DELTA_NOT_CLASSIFIED")
    blocked=classify_source_delta(
        [{"ref":{"kind":"UNKNOWN_SEMANTIC_SOURCE"},"observed_sha256":"old"}],
        [{"ref":{"kind":"UNKNOWN_SEMANTIC_SOURCE"},"observed_sha256":"new"}])
    require(blocked["status"]=="BLOCKED_UNCLASSIFIED_SOURCE_DELTA",
            "UNKNOWN_SOURCE_DELTA_NOT_BLOCKED")
    print(json.dumps({"test_code": CODE, "self_test": "PASS",
       "negative": "PASS", "live_pipeline_pass": False}))
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--live", action="store_true")
    p.add_argument("--rollback-e2e", action="store_true")
    p.add_argument("--cohort", choices=sorted(COHORTS))
    p.add_argument("--output", default=".lf_ci/m9_3_live_diagnostic.json")
    args = p.parse_args()
    if args.self_test:
        return self_test()
    require(args.live, "EXPLICIT_LIVE_FLAG_REQUIRED")
    return run_live(Path(args.output), rollback_e2e=args.rollback_e2e, cohort=args.cohort)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError) as exc:
        print(json.dumps({"test_code": CODE, "status": "BLOCKED",
            "error_type": type(exc).__name__, "error_code": str(exc),
            "test_exit_code": 1}))
        sys.exit(1)
