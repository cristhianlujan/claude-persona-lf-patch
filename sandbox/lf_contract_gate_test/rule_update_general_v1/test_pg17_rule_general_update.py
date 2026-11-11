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
GENERAL = ROOT / "supabase/migrations/20261111100000_lf_rule_update_general_admin_functional_v1.sql"
CONTRACT_FIXTURE = ROOT / "sandbox/lf_contract_gate_test/rule_update_general_v1/lf_rule_operation_contract_pg17_fixture.sql"
STATE_AWARE = ROOT / "supabase/migrations/20261111115000_lf_rule_update_child_readback_state_aware_v1.sql"
READBACK_BASELINE = ROOT / "sandbox/lf_contract_gate_test/rule_update_bulk_v1/lf_rule_child_readback_live_source_fixture.sql"


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
    for f in (FIXTURE, SEED, MIGRATION, HISTORY, CONTRACT_FIXTURE, GENERAL, READBACK_BASELINE, STATE_AWARE):
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
    sql(CONTRACT_FIXTURE.read_text(encoding="utf-8"))
    # A governed Product Director parent is installed by the synthetic seed.
    # The mode migration requires its exact real-in-database execution id,
    # never a synthetic ID hardcoded inside the production migration.
    sql("SET lf.rule_update_governance_execution_id = '"+PARENT+"';\n"
        +GENERAL.read_text(encoding="utf-8"))
    sql(READBACK_BASELINE.read_text(encoding="utf-8"))
    sql(STATE_AWARE.read_text(encoding="utf-8"))
    verify("STATE_AWARE_CHILD_READBACK_INSTALLED",
           "RULE_CHILD_ADMIN_HISTORY_OR_STATE_MISMATCH" in
           sql("SELECT pg_get_functiondef("
               "'public.lf_skill_rule_child_readback_v1(text,text,text)'"
               "::regprocedure)"))
    # Contract is conditional for ADMINISTRATIVE_ONLY only; legacy default
    # candidate and direct-VIGENTE/functional guardrails must survive.
    override=json.loads(sql("SELECT allowed#>>'{mode_overrides,ADMINISTRATIVE_ONLY}' "
                            "FROM public.lf_operation_contracts "
                            "WHERE operation_code='ACTUALIZACION_REGLA_LF'"))
    verify("ADMIN_CONTRACT_EXACT_MODE_SCOPED",
           override["mode"]=="ADMINISTRATIVE_ONLY"
           and override["operation_code"]=="ACTUALIZACION_REGLA_LF"
           and override["skill_code"]=="RULE_UPDATE_APPLY"
           and override["parent_profile"]=="PERFIL-PRODUCT-DIRECTOR-LF"
           and override["allowed_states"]==["CANDIDATO","VIGENTE"]
           and override["allowed_fields"]==["created_by","owner_name"]
           and override["legacy_state_gate_override_only_this_mode"] is True)
    verify("ADMIN_OWNER_GUARD_DISTINCT",
           override["functional_owner"]=="LF_GOVERNANCE"
           and override["governance_guard"]=="SUPER_ADMIN"
           and override["functional_owner"]!=override["governance_guard"]
           and override["guard_receipt_required"] is True)
    verify("ADMIN_WRITER_POLICY_GUARD_ENFORCED",
           "BLOCK_RULE_ADMIN_GOVERNANCE_GUARD_OR_OWNER_MISMATCH" in
           GENERAL.read_text(encoding="utf-8"))
    verify("ADMIN_CONTRACT_STATE_AND_HISTORY_REQUIRED",
           override["preserve_existing_state"] is True
           and override["governed_child_required"] is True
           and override["judge_step70_clean_required"] is True
           and "immutable_history" in override["after_write"]
           and override["no_promotion"] is True)
    verify("ADMIN_CONTRACT_LEGACY_CANDIDATE_AND_VIGENTE_BLOCK",
           sql("SELECT (allowed->>'write_state'='CANDIDATO' "
               "AND blocked->>'vigente_direct_update'='true' "
               "AND blocked->>'vigente_functional_change'='true' "
               "AND blocked->>'production_promotion'='true' "
               "AND required_after_write ? 'estado_CANDIDATO') "
               "FROM public.lf_operation_contracts "
               "WHERE operation_code='ACTUALIZACION_REGLA_LF'")=="t")
    verify("ADMIN_CONTRACT_PARENT_GOVERNED_TRACE",
           sql("SELECT updated_by_execution_id FROM public.lf_operation_contracts "
               "WHERE operation_code='ACTUALIZACION_REGLA_LF'")==PARENT)
    verify("GENERAL_METADATA_MODE_BOUND",
           sql("SELECT destination_kind FROM public.lf_operation_mode_bindings "
               "WHERE operation_code='ACTUALIZACION_REGLA_LF' AND "
               "task_mode='MAINTAIN_METADATA' AND execution_mode='GOVERNED'")
           =="CANONICAL_EXISTING")
    verify("GENERAL_WRITER_INSTALLED",
           sql("SELECT to_regprocedure("
               "'public.lf_regla_admin_governed_write_v1(text,text,text,jsonb)'"
               ") IS NOT NULL")=="t")
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
    # Reuse the original judged Product Director parent as the only authority.
    def set_parent_patch(patch: dict, verified_parity: bool = False) -> None:
        raw = json.dumps(patch, ensure_ascii=False, sort_keys=True).replace("'", "''")
        sql("UPDATE public.lf_operation_execution_steps "
            "SET evidence_payload=jsonb_set(evidence_payload,"
            "'{profile_output,deliverable_created,governed_rule_patch}',"
            f"'{raw}'::jsonb) WHERE execution_id='{PARENT}'"
            " AND step_id='execute_profile';")
        if verified_parity:
            sql("UPDATE public.lf_operation_execution_steps "
                "SET evidence_payload=jsonb_set(evidence_payload,"
                "'{profile_output,deliverable_created,product_decision,material_parity}',"
                "'\"VERIFIED\"'::jsonb) "
                f"WHERE execution_id='{PARENT}' AND step_id='execute_profile';")
        else:
            sql("UPDATE public.lf_operation_execution_steps "
                "SET evidence_payload=evidence_payload#-"
                "'{profile_output,deliverable_created,product_decision,material_parity}' "
                f"WHERE execution_id='{PARENT}' AND step_id='execute_profile';")

    admin_patch = {"rule_code": CODE, "change_kind": "ADMINISTRATIVE_ONLY",
                   "changes": {"owner_name": "SUPER_ADMIN", "created_by": "ChatGPT"}}
    set_parent_patch(admin_patch)
    expect_block("RUN-NO-OWNER-COLUMN-001",
                 "BLOCK_RULE_ADMIN_OWNER_COLUMN_NOT_YET_INSTALLED",
                 patch=admin_patch)
    verify("NO_ADMIN_WRITE_WHEN_SCHEMA_ABSENT",
           sql(f"SELECT created_by FROM lf_ops.reglas WHERE codigo='{CODE}'")
           == "TEST_FIXTURE")
    # Temporary column exists ONLY in isolated PG17; production schema remains
    # untouched and needs separately governed schema-impact remediation.
    sql("ALTER TABLE lf_ops.reglas ADD COLUMN owner_name text;")
    sql(invocation("RUN-ADMIN-VIGENTE-001","EXEC-SKILL-ADMIN-VIGENTE-001",
                   patch=admin_patch))
    out=sql(apply("RUN-ADMIN-VIGENTE-001","EXEC-SKILL-ADMIN-VIGENTE-001",
                  patch=admin_patch))
    verify("ADMIN_VIGENTE_GOVERNED_WRITE", "APPLIED_VERIFIED" in out)
    verify("ADMIN_VIGENTE_STATUS_PRESERVED",
           sql(f"SELECT estado FROM lf_ops.reglas WHERE codigo='{CODE}'")
           =="VIGENTE")
    verify("ADMIN_VIGENTE_OFFICIAL_SKILL_CHILD_READBACK",
           json.loads(sql("SELECT public.lf_skill_rule_child_readback_v1("
               "'"+PARENT+"','RUN-ADMIN-VIGENTE-001',"
               "'EXEC-SKILL-ADMIN-VIGENTE-001')"))["status"]=="APPLIED_VERIFIED")
    verify("ADMIN_OWNER_AND_CREATOR_WRITTEN",
           sql(f"SELECT owner_name||':'||created_by FROM lf_ops.reglas "
               f"WHERE codigo='{CODE}'")=="SUPER_ADMIN:ChatGPT")
    verify("ADMIN_HISTORY_SAVED_IN_CANONICAL_STEP",
           sql("SELECT evidence_payload#>>'{rule_update_history_v1,change_kind}' "
               "FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-ADMIN-VIGENTE-001' "
               "AND step_id='readback'")=="ADMINISTRATIVE_ONLY")
    verify("ADMIN_HISTORY_OLD_ACTOR_PRESERVED",
           sql("SELECT evidence_payload#>>'{rule_update_history_v1,source_row,created_by}' "
               "FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-ADMIN-VIGENTE-001' "
               "AND step_id='readback'")=="TEST_FIXTURE")
    verify("ADMIN_CHANGED_FIELDS_ONLY",
           sql("SELECT (SELECT count(*) FROM jsonb_object_keys("
               "evidence_payload#>'{rule_update_history_v1,changed_fields}')) "
               "FROM public.lf_operation_execution_steps WHERE "
               "execution_id='EXEC-SKILL-ADMIN-VIGENTE-001' "
               "AND step_id='readback'")=="2")
    protected_admin={"rule_code":CODE,"change_kind":"ADMINISTRATIVE_ONLY",
                     "changes":{"estado":"CANDIDATO"}}
    expect_block("RUN-ADMIN-PROTECTED-001",
                 "BLOCK_RULE_CHILD_PROTECTED_OR_INVALID_FIELD",
                 patch=protected_admin)

    functional_patch={"rule_code":CODE,"change_kind":"FUNCTIONAL_CANDIDATE",
                      "changes":{"valor_config":{"existing":True,"limit":5}}}
    set_parent_patch(functional_patch,verified_parity=True)
    expect_block("RUN-FUNCTIONAL-VIGENTE-001",
                 "BLOCK_RULE_FUNCTIONAL_CHANGE_REQUIRES_SUPERSESSION",
                 patch=functional_patch)
    verify("FUNCTIONAL_VIGENTE_NOT_CHANGED",
           sql(f"SELECT valor_config FROM lf_ops.reglas WHERE codigo='{CODE}'")
           =='{"existing": true}')
    # Synthetic setup only: mimic an existing unpromoted candidate.
    sql(f"UPDATE lf_ops.reglas SET estado='CANDIDATO' WHERE codigo='{CODE}';")
    set_parent_patch(functional_patch,verified_parity=False)
    expect_block("RUN-FUNCTIONAL-NO-PARITY-001",
                 "BLOCK_RULE_FUNCTIONAL_SEMANTIC_PARITY_NOT_VERIFIED",
                 patch=functional_patch)
    # Only a real register entry + an exact source reference in the judged
    # Product output can authorize a functional candidate modification.
    sql("CREATE TABLE public.lf_decisiones_gov "
        "(id_decision text PRIMARY KEY,estado_normalizado text);")
    set_parent_patch(functional_patch,verified_parity=True)
    expect_block("RUN-FUNCTIONAL-MISSING-DECISION-001",
                 "BLOCK_RULE_FUNCTIONAL_ORIGINAL_AUTHORITY_UNVERIFIED",
                 patch=functional_patch)
    sql("INSERT INTO public.lf_decisiones_gov(id_decision,estado_normalizado) "
        "VALUES('PG17-DOC-001','CANDIDATO_CONTROLADO');")
    expect_block("RUN-FUNCTIONAL-PENDING-DECISION-001",
                 "BLOCK_RULE_FUNCTIONAL_ORIGINAL_AUTHORITY_UNVERIFIED",
                 patch=functional_patch)
    sql("UPDATE public.lf_decisiones_gov SET estado_normalizado='VIGENTE' "
        "WHERE id_decision='PG17-DOC-001';")
    expect_block("RUN-FUNCTIONAL-MISSING-EXACT-REF-001",
                 "BLOCK_RULE_FUNCTIONAL_ORIGINAL_AUTHORITY_UNVERIFIED",
                 patch=functional_patch)
    sql("UPDATE public.lf_operation_execution_steps SET evidence_payload="
        "jsonb_set(evidence_payload,"
        "'{profile_output,deliverable_created,product_decision,source_refs}',"
        "'[{\"authority\":\"AUTHORITATIVE\",\"current\":true,"
        "\"source_ref\":\"supabase://lf_decisiones_gov/PG17-DOC-001\"}]'::jsonb) "
        f"WHERE execution_id='{PARENT}' AND step_id='execute_profile';")
    sql(invocation("RUN-FUNCTIONAL-CANDIDATE-001",
                   "EXEC-SKILL-FUNCTIONAL-CANDIDATE-001",
                   patch=functional_patch))
    out=sql(apply("RUN-FUNCTIONAL-CANDIDATE-001",
                  "EXEC-SKILL-FUNCTIONAL-CANDIDATE-001",
                  patch=functional_patch))
    verify("FUNCTIONAL_CANDIDATE_GOVERNED_WRITE",
           "APPLIED_VERIFIED" in out)
    verify("FUNCTIONAL_CANDIDATE_CONFIG_UPDATED",
           json.loads(sql(f"SELECT valor_config FROM lf_ops.reglas "
                          f"WHERE codigo='{CODE}'")) ==
           {"existing":True,"limit":5})
    verify("FUNCTIONAL_CHANGE_HISTORY_RECORDED",
           sql("SELECT evidence_payload#>>'{rule_update_history_v1,change_kind}' "
               "FROM public.lf_operation_execution_steps "
               "WHERE execution_id='EXEC-SKILL-FUNCTIONAL-CANDIDATE-001' "
               "AND step_id='readback'")=="FUNCTIONAL_CANDIDATE")
    verify("FUNCTIONAL_NOT_PROMOTED",
           sql(f"SELECT estado FROM lf_ops.reglas WHERE codigo='{CODE}'")
           =="CANDIDATO")

    print(json.dumps({
        "status": "ISOLATED_PG17_RULE_GENERAL_UPDATE_PASS",
        "official_writer_used": "lf_regla_candidate_write_v1",
        "canonical_recorder_used": "lf_record_operation_step_core_v1",
        "same_parent": True, "production_write": False,
        "promotion_executed": False,
        "semantic_model_executed": False,
        "fixture_semantic_decision": True
    }, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
