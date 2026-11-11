#!/usr/bin/env python3
"""Isolated PG17: candidate-only rule child, real canonical writer/core and rollback.

This does not claim GPT semantic judgment: parent RAW/step70 here are synthetic
fixtures, used to test runtime *enforcement*. It touches no official Supabase DB.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
DB = os.environ.get("PGDATABASE","postgres")
PARENT = "EXEC-PROFILE-GATE2-PG17RULECHILD001"
CODE = "TEST-RULE-DOC-001"
OLD = "Descripcion original validada"
NEW = "Descripcion corregida documentada y autorizada por el perfil"
FIXTURE = ROOT / "sandbox/lf_contract_gate_test/db_write_transport/lf_rule_child_pg17_original_source_fixture_v1.sql"
SEED = ROOT / "sandbox/lf_contract_gate_test/db_write_transport/lf_rule_child_pg17_seed_v1.sql"
MIGRATION = ROOT / "supabase/migrations/20261109092529_lf_profile_rule_update_child_execution_v1.sql"
HISTORY = ROOT / "supabase/migrations/20261111080000_lf_rule_update_history_evidence_v1.sql"


def sql(script: str, *, expect_fail: bool = False) -> str:
    cmd = ["psql", "-X", "-A", "-t", "-q",
           "-v", "ON_ERROR_STOP=1", "-d", DB]
    env = dict(os.environ)
    env.setdefault("PGHOST","127.0.0.1")
    env.setdefault("PGUSER","postgres")
    p = subprocess.run(cmd, input=script, text=True, capture_output=True, timeout=50, env=env)
    if expect_fail:
        if p.returncode == 0:
            raise AssertionError("BLOCK_EXPECTED_PG_FAILURE_BUT_SUCCEEDED")
        return p.stderr
    if p.returncode != 0:
        raise AssertionError("BLOCK_ISOLATED_PG_ERROR:" + p.stderr[-1700:])
    return p.stdout.strip()


def verify(code: str, ok: bool) -> None:
    if not ok:
        raise AssertionError("BLOCK_" + code)
    print("PASS_" + code, flush=True)


def candidate_patch(changes: dict[str, str] | None = None) -> dict:
    return {"rule_code": CODE, "change_kind": "DOCUMENTARY_ONLY",
            "changes": changes or {"descripcion": NEW}}


def packet_sql(*, patch: dict | None = None, stale: bool = False) -> str:
    candidate = json.dumps(patch or candidate_patch(), ensure_ascii=False, sort_keys=True)
    candidate_literal = candidate.replace("'", "''")
    shot = "'0'::text||repeat('0',63)" if stale else f"public.lf_asset_snapshot_sha_v1('REGLA','{CODE}')"
    return ("jsonb_build_object("
            f"'regla_codigo','{CODE}',"
            f"'analysis_snapshot_sha256',{shot},"
            "'decision_id','PG17-DOC-001',"
            f"'candidate_patch','{candidate_literal}'::jsonb)")


def invocation(run: str, child: str, *, patch: dict | None = None,
               stale: bool = False) -> str:
    inp = packet_sql(patch=patch, stale=stale)
    return (
        "INSERT INTO public.lf_skill_invocation_v1 "
        "(skill_run_id,skill_code,parent_execution_id,profile_code,status,"
        "input_sha256,child_execution_id) SELECT "
        f"'{run}','RULE_UPDATE_APPLY','{PARENT}',"
        "'PERFIL-PRODUCT-DIRECTOR-LF','COMPLETED',"
        f"encode(extensions.digest(convert_to(({inp})::text,'UTF8'),'sha256'),'hex'),"
        f"'{child}';")


def apply(run: str, child: str, *, patch: dict | None = None,
          stale: bool = False) -> str:
    return (
        "SELECT public.lf_skill_o_rule_update_v1("
        f"'{child}',{packet_sql(patch=patch, stale=stale)},"
        f"'{PARENT}','{run}',repeat('f',64));")


def expect_block(run: str, code: str, *, patch: dict | None = None,
                 stale: bool = False) -> None:
    child = "EXEC-SKILL-" + run.replace("RUN-", "")
    sql(invocation(run, child, patch=patch, stale=stale))
    error = sql(apply(run, child, patch=patch, stale=stale), expect_fail=True)
    verify(code, code in error and
           sql(f"SELECT count(*) FROM public.lf_operation_execution WHERE execution_id='{child}'") == "0")


def main() -> None:
    for f in (FIXTURE, SEED, MIGRATION, HISTORY):
        verify("SOURCE_FILE_EXISTS_" + f.stem.upper(), f.is_file())
    sql(FIXTURE.read_text(encoding="utf-8"))
    expected = {
        "lf_skill_invoke_v1": "884b551f9dd11919c6c8488ee34f197f",
        "lf_regla_candidate_write_v1": "c311087befe49afb2affa668231c9dd1",
        "lf_record_operation_step_core_v1": "fe08a25c8e3c023d7181194d2dfdee0d",
    }
    for name, digest in expected.items():
        signature = {
            "lf_skill_invoke_v1": "text,text,jsonb",
            "lf_regla_candidate_write_v1": "text,text,text,text,text,text,text,jsonb,boolean,text",
            "lf_record_operation_step_core_v1": "text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text",
        }[name]
        actual = sql(f"SELECT md5(pg_get_functiondef('public.{name}({signature})'::regprocedure))")
        verify("FROZEN_SOURCE_" + name.upper(), actual == digest)
    sql(SEED.read_text(encoding="utf-8"))
    sql(MIGRATION.read_text(encoding="utf-8"))
    verify("SOURCE_BASELINE_MATCHES_LIVE",
        sql("SELECT md5(pg_get_functiondef("
            "'public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)'"
            "::regprocedure))")=="dc97a0e7c65b65ae1951e2da86c6238b")
    sql(HISTORY.read_text(encoding="utf-8"))
    verify("SKILL_OPENER_BOUND",
           sql("SELECT opener_fn FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_UPDATE_APPLY'") ==
           "lf_skill_o_rule_update_v1")
    verify("NO_ROUTER_SOURCE_MUTATION",
           "lf_router_pipeline_context" not in MIGRATION.read_text(encoding="utf-8"))

    # True transactional reversal of all effects. Parent + rule are fixtures.
    trans = ("BEGIN;\n"
             + invocation("RUN-ROLLBACK-001", "EXEC-SKILL-ROLLBACK-001") + "\n"
             + apply("RUN-ROLLBACK-001", "EXEC-SKILL-ROLLBACK-001") + "\n"
             + "ROLLBACK;\n")
    out = sql(trans)
    verify("SUCCESSFUL_APPLY_CAN_BE_ROLLED_BACK", "APPLIED_VERIFIED" in out)
    verify("ROLLBACK_RESTORES_RULE",
           sql(f"SELECT descripcion FROM lf_ops.reglas WHERE codigo='{CODE}'") == OLD)
    verify("ROLLBACK_NO_CHILD_ROWS",
           sql("SELECT count(*) FROM public.lf_operation_execution "
               "WHERE execution_id='EXEC-SKILL-ROLLBACK-001'") == "0")
    verify("ROLLBACK_NO_STEP_RESIDUE",
           sql("SELECT count(*) FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-ROLLBACK-001'") == "0")

    sql(invocation("RUN-VALID-001", "EXEC-SKILL-VALID-001"))
    out = sql(apply("RUN-VALID-001", "EXEC-SKILL-VALID-001"))
    verify("CANDIDATE_PATCH_APPLIED_VERIFIED", "APPLIED_VERIFIED" in out)
    verify("EXACT_TARGET_CONTENT_CHANGED",
           sql(f"SELECT descripcion FROM lf_ops.reglas WHERE codigo='{CODE}'") == NEW)
    verify("SEVEN_CANONICAL_JUDGED_STEPS",
           sql("SELECT count(*) FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-VALID-001' AND status='PASS_CLEAN'") == "7")
    verify("CHILD_COMPLETED_ON_SAME_PARENT",
           sql("SELECT status||':'||created_by_execution_id FROM public.lf_operation_execution "
               "WHERE execution_id='EXEC-SKILL-VALID-001'") == "COMPLETED:" + PARENT)
    verify("CANDIDATE_NOT_PROMOTED",
           sql(f"SELECT estado||':'||pendiente_decision::text FROM lf_ops.reglas WHERE codigo='{CODE}'")
           == "CANDIDATO:true")
    verify("MATERIAL_CONFIGURATION_PRESERVED",
           json.loads(sql(f"SELECT valor_config FROM lf_ops.reglas WHERE codigo='{CODE}'")) == {"existing": True})
    verify("SNAPSHOT_RECORDED_IN_CHILD",
           sql("SELECT (manifest->>'result_snapshot_sha256')="
               f"public.lf_asset_snapshot_sha_v1('REGLA','{CODE}') FROM public.lf_operation_execution "
               "WHERE execution_id='EXEC-SKILL-VALID-001'") == "t")

    # Full two-sided evidence is stored in the existing official readback step.
    history_ref=("SELECT evidence_payload->'rule_update_history_v1' "
                 "FROM public.lf_operation_execution_steps "
                 "WHERE execution_id='EXEC-SKILL-VALID-001' AND step_id='readback'")
    history=json.loads(sql(history_ref))
    verify("COMPLETE_SOURCE_PREIMAGE",
           history["source_row"]["descripcion"]==OLD
           and history["source_row"]["codigo"]==CODE)
    verify("COMPLETE_RESULT_POSTIMAGE",
           history["result_row"]["descripcion"]==NEW
           and history["result_row"]["codigo"]==CODE)
    verify("SOURCE_SNAPSHOT_SHA_FROM_FULL_ROW",
           sql("SELECT encode(extensions.digest(convert_to(("
               "(evidence_payload#>'{rule_update_history_v1,source_row}')"
               "-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')"
               "=(evidence_payload#>>"
               "'{rule_update_history_v1,source_snapshot_sha256}')"
               " FROM public.lf_operation_execution_steps WHERE "
               "execution_id='EXEC-SKILL-VALID-001' AND step_id='readback'")=="t")
    verify("RESULT_SNAPSHOT_SHA_FROM_FULL_ROW",
           sql("SELECT encode(extensions.digest(convert_to(("
               "(evidence_payload#>'{rule_update_history_v1,result_row}')"
               "-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')"
               "=(evidence_payload#>>"
               "'{rule_update_history_v1,result_snapshot_sha256}')"
               " FROM public.lf_operation_execution_steps WHERE "
               "execution_id='EXEC-SKILL-VALID-001' AND step_id='readback'")=="t")
    verify("COMPLETE_CHANGES_EXACT",
           history["changed_fields"]["descripcion"]["before"]==OLD and
           history["changed_fields"]["descripcion"]["after"]==NEW)
    verify("HISTORY_BINDS_APPROVED_PARENT",
           history["parent_execution_id"]==PARENT and
           history["child_execution_id"]=="EXEC-SKILL-VALID-001" and
           history["authorized_operation"]=="ACTUALIZACION_REGLA_LF")
    verify("NO_HISTORY_ON_ROLLED_BACK_EXECUTION",
           sql("SELECT COUNT(*) FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-ROLLBACK-001' AND "
               "evidence_payload ? 'rule_update_history_v1'")=="0")
    verify("RULES_TABLE_STILL_UNCHANGED_SCHEMA",
           sql("SELECT to_regclass('lf_ops.reglas_owner_metadata_v1') IS NULL")=="t")
    history_access=sql("SELECT COUNT(*) FROM public.lf_operation_execution e "
       "JOIN public.lf_operation_execution_steps st ON st.execution_id=e.execution_id "
       "WHERE e.operation_code='ACTUALIZACION_REGLA_LF' "
       "AND e.target_code='"+CODE+"' AND e.status='COMPLETED' "
       "AND st.step_id='readback' AND st.status='PASS_CLEAN' "
       "AND st.evidence_payload ? 'rule_update_history_v1'")
    verify("HISTORY_QUERY_BY_RULE_WITH_EXISTING_EXECUTIONS",history_access=="1")
    error=sql("UPDATE public.lf_operation_execution_steps SET evidence_payload="
              "jsonb_set(evidence_payload,"
              "'{rule_update_history_v1,result_row,descripcion}',"
              "'\"FALSO\"'::jsonb) "
              "WHERE execution_id='EXEC-SKILL-VALID-001' "
              "AND step_id='readback';",expect_fail=True)
    verify("CANNOT_TAMPER_WITH_SAVED_HISTORY",
           "BLOCK_RULE_HISTORY_IMMUTABLE_UPDATE" in error)
    error=sql("UPDATE public.lf_operation_execution_steps SET status='FAILED' "
              "WHERE execution_id='EXEC-SKILL-VALID-001' "
              "AND step_id='readback';",expect_fail=True)
    verify("CANNOT_DEMOTE_HISTORY_STEP", "BLOCK_RULE_HISTORY_IMMUTABLE_UPDATE" in error)
    error=sql("DELETE FROM public.lf_operation_execution_steps "
              "WHERE execution_id='EXEC-SKILL-VALID-001' "
              "AND step_id='readback';",expect_fail=True)
    verify("CANNOT_DELETE_RULE_HISTORY",
           "BLOCK_RULE_HISTORY_IMMUTABLE_DELETE" in error)
    verify("HISTORY_SURVIVES_NEGATIVE_ATTEMPTS",
           sql("SELECT count(*) FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-VALID-001' "
               "AND step_id='readback' AND "
               "evidence_payload ? 'rule_update_history_v1'")=="1")

    # Fail closed. Each child run is new; the original official candidate stays intact.
    expect_block("RUN-STALE-001", "BLOCK_RULE_CHILD_SOURCE_SNAPSHOT_STALE", stale=True)
    forged = candidate_patch({"descripcion": "Descripcion manipulada sin autoridad material del perfil"})
    expect_block("RUN-FORGE-001", "BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT", patch=forged)
    protected = candidate_patch({"valor_config": "formato de ataque no permitido"})
    expect_block("RUN-PROTECTED-001", "BLOCK_RULE_CHILD_PROTECTED_OR_INVALID_FIELD", patch=protected)
    sql("UPDATE public.lf_profile_write_authority_v1 SET status='RETIRED';")
    expect_block("RUN-NOAUTH-001", "BLOCK_RULE_CHILD_PROFILE_OPERATION_AUTHORITY")
    sql("UPDATE public.lf_profile_write_authority_v1 SET status='ACTIVE';")
    sql("UPDATE public.lf_operation_execution_steps SET status='BLOCKED_STEP_NOT_CLEAN' "
        f"WHERE execution_id='{PARENT}' AND step_id='semantic_judge';")
    expect_block("RUN-NOJUDGE-001", "BLOCK_RULE_CHILD_SEMANTIC_JUDGE_NOT_CLEAN")
    sql("UPDATE public.lf_operation_execution_steps SET status='STEP_PASS_WITH_EVIDENCE' "
        f"WHERE execution_id='{PARENT}' AND step_id='semantic_judge';")
    sql(f"UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,"
        "'{screen_selection_result,selected_screen_code}',"
        "'\"OTHER-SCREEN\"'::jsonb) WHERE execution_id='"
        + PARENT + "';")
    expect_block("RUN-NOSCREEN-001", "BLOCK_RULE_CHILD_RULE_NOT_IN_SELECTED_SCREEN")
    sql("UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,"
        "'{screen_selection_result,selected_screen_code}',"
        "'\"B2B-AUTH-001\"'::jsonb) WHERE execution_id='" + PARENT + "';")
    sql(f"UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo='{CODE}';")
    expect_block("RUN-VIGENTE-001", "BLOCK_RULE_CHILD_REQUIRES_CANDIDATO")
    verify("NEGATIVE_PROBES_DO_NOT_CREATE_CHILDREN",
           sql("SELECT count(*) FROM public.lf_operation_execution "
               "WHERE execution_id LIKE 'EXEC-SKILL-%'") == "1")
    print(json.dumps({
        "status": "ISOLATED_PG17_RULE_HISTORY_PASS",
        "official_writer_used": "lf_regla_candidate_write_v1",
        "canonical_recorder_used": "lf_record_operation_step_core_v1",
        "same_parent": True, "production_write": False,
        "promotion_executed": False,
        "semantic_model_executed": False,
        "fixture_semantic_decision": True
    }, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
