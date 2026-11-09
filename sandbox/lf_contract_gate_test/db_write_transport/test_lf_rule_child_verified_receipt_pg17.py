#!/usr/bin/env python3
"""Governed rule-child receipt: real PG17 positive, replay, and falsification.

Uses source-frozen canonical functions, synthetic producer/judge inputs, and
an ephemeral PostgreSQL Docker container. Never uses Supabase credentials.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
CONTAINER=os.environ.get("PG_CONTAINER","")
BASE=ROOT/"sandbox/lf_contract_gate_test/db_write_transport/"
ORIG=BASE/"lf_rule_child_pg17_original_source_fixture_v1.sql"
SEED=BASE/"lf_rule_child_pg17_seed_v1.sql"
C31=ROOT/"supabase/migrations/20261109092529_lf_profile_rule_update_child_execution_v1.sql"
C32=ROOT/"supabase/migrations/20261109121500_lf_profile_rule_child_verified_return_v1.sql"
HANDLER=BASE/"lf_rule_child_receipt_pg17_handler_source_v1.sql"
PARENT="EXEC-PROFILE-GATE2-PG17RULECHILD001"
RULE="TEST-RULE-DOC-001"
PATCH={"rule_code":RULE,"change_kind":"DOCUMENTARY_ONLY","changes":{"descripcion":"Descripcion corregida documentada y autorizada por el perfil"}}
EXPECTED_HASH="884b551f9dd11919c6c8488ee34f197f"

def query(sql, db="postgres", fail=False):
    p=subprocess.run(
        ["docker","exec","-i",CONTAINER,"psql","-X","-A","-t","-q",
         "-v","ON_ERROR_STOP=1","-U","postgres","-d",db],
        input=sql,capture_output=True,text=True,timeout=35)
    if fail:
        if p.returncode == 0: raise AssertionError("NEGATIVE_EXPECTED_FAILURE")
        return p.stderr.strip()
    if p.returncode:
        raise AssertionError("POSTGRESQL_FAILED:"+p.stderr[-2000:])
    return p.stdout.strip()

def test(ok, code):
    if not ok: raise AssertionError("FAIL_"+code)
    print("PASS_"+code,flush=True)

def input_json():
    return json.dumps({
        "regla_codigo":RULE,
        "analysis_snapshot_sha256":query("SELECT public.lf_asset_snapshot_sha_v1('REGLA','TEST-RULE-DOC-001')"),
        "decision_id":"PG17-DOC-001",
        "candidate_patch":PATCH,
    },ensure_ascii=False,sort_keys=True)

def invoke(json_str):
    escaped=json_str.replace("'","''")
    return json.loads(query(
       "SELECT public.lf_skill_invoke_v1("
       "'RULE_UPDATE_APPLY','EXEC-PROFILE-GATE2-PG17RULECHILD001',"
       f"'{escaped}'::jsonb);"))

def main():
    test(bool(CONTAINER),"EPHEMERAL_DOCKER_TARGET_PRESENT")
    for path in [ORIG,SEED,C31,C32,HANDLER]:
        test(path.is_file(),"SOURCE_EXISTS_"+path.stem.upper())
    query(ORIG.read_text(encoding="utf-8"))
    test(query("SELECT md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))")==EXPECTED_HASH,
         "EXACT_ORIGINAL_INVOKER_SOURCE")
    query(SEED.read_text(encoding="utf-8"))
    query(C31.read_text(encoding="utf-8"))
    query(HANDLER.read_text(encoding="utf-8"))
    test(query("SELECT opener_fn FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_UPDATE_APPLY'")=="lf_skill_o_rule_update_v1",
         "RULE_CHILD_OPENER_EXISTS")
    query(C32.read_text(encoding="utf-8"))
    test(query("SELECT count(*) FROM pg_proc WHERE oid='public.lf_skill_rule_child_readback_v1(text,text,text)'::regprocedure")=="1",
         "RECEIPT_RESOLVER_INSTALLED")
    test(query("SELECT has_function_privilege('anon','public.lf_skill_rule_child_readback_v1(text,text,text)','EXECUTE')")=="f",
         "NO_ANON_RECEIPT_EXECUTION")
    test(query("SELECT has_function_privilege('authenticated','public.lf_skill_rule_child_readback_v1(text,text,text)','EXECUTE')")=="f",
         "NO_AUTHENTICATED_RECEIPT_EXECUTION")
    test(query("SELECT has_function_privilege('service_role','public.lf_skill_rule_child_readback_v1(text,text,text)','EXECUTE')")=="t",
         "EXISTING_SERVICE_ROLE_CAN_READ_RECEIPT")

    packet=input_json()
    original=invoke(packet)
    test(original.get("status")=="COMPLETED","SKILL_INVOKER_RETURN_COMPLETED")
    test(original.get("effect_verified") is True,"SKILL_INVOKER_RETURN_EFFECT_VERIFIED")
    test(original.get("next_action")=="CONTINUE_PROFILE","SKILL_INVOKER_REQUIRES_SAME_PARENT")
    rec=original.get("child_receipt")
    test(isinstance(rec,dict) and rec.get("status")=="APPLIED_VERIFIED",
         "CHILD_RECEIPT_CANONICAL_APPLIED_VERIFIED")
    child=original["child_execution_id"];run=original["skill_run_id"]
    test(rec.get("parent_execution_id")==PARENT and rec.get("child_execution_id")==child
         and rec.get("skill_run_id")==run,
         "CHILD_RECEIPT_EXACT_PARENT_AND_SKILL_IDS")
    test(rec.get("profile_execution_complete") is False and
         rec.get("promotion_authorized") is False,
         "NO_FALSE_TERMINALITY_OR_PROMOTION")
    test(query("SELECT count(*) FROM public.lf_operation_execution_steps "
          f"WHERE execution_id='{child}' AND status='PASS_CLEAN'")=="7",
          "SEVEN_CORE_JUDGED_STEPS_PERSISTED")
    test(query(f"SELECT estado||':'||pendiente_decision::text FROM lf_ops.reglas WHERE codigo='{RULE}'")=="CANDIDATO:true",
         "CANONICAL_RULE_REMAINS_CANDIDATE")
    test(query(f"SELECT status FROM public.lf_operation_execution WHERE execution_id='{PARENT}'")=="IN_PROGRESS",
         "PARENT_STILL_IN_PROGRESS")
    replay=invoke(packet)
    test(replay.get("replay") is True and replay.get("effect_verified") is True,
         "IDEMPOTENT_REPLAY_VERIFIED")
    test(replay["skill_run_id"]==run and replay["child_execution_id"]==child and
         replay.get("child_receipt",{}).get("result_snapshot_sha256")==rec.get("result_snapshot_sha256"),
         "IDEMPOTENT_REPLAY_SAME_CHILD_AND_HASH")
    test(query("SELECT count(*) FROM public.lf_skill_invocation_v1")=="1",
         "REPLAY_NO_NEW_SKILL_ROWS")
    test(query("SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_REGLA_LF'")=="1",
         "REPLAY_NO_NEW_CHILD_ROWS")
    verify=f"SELECT public.lf_skill_rule_child_readback_v1('{PARENT}','{run}','{child}');"
    test(json.loads(query(verify)).get("status")=="APPLIED_VERIFIED",
         "RECEIPT_RECHECK_SUCCESSFUL")
    test(json.loads(query(
      f"SELECT public.lf_skill_rule_child_readback_v1('EXEC-PROFILE-GATE2-IMPOSTOR001','{run}','{child}');"
    )).get("code")=="RULE_CHILD_INVOCATION_MISMATCH","FORGED_PARENT_BLOCKED")
    test(json.loads(query(
      f"SELECT public.lf_skill_rule_child_readback_v1('{PARENT}','RUN-IMPOSTOR001','{child}');"
    )).get("code")=="RULE_CHILD_INVOCATION_MISMATCH","FORGED_SKILL_RUN_BLOCKED")

    query(f"UPDATE public.lf_operation_execution SET status='IN_PROGRESS' WHERE execution_id='{child}';")
    test(json.loads(query(verify)).get("status")=="CHILD_IN_PROGRESS",
         "OPEN_CHILD_NOT_MISTAKEN_FOR_APPLIED")
    query(f"UPDATE public.lf_operation_execution SET status='COMPLETED' WHERE execution_id='{child}';")

    query(f"UPDATE public.lf_operation_execution_steps SET status='BLOCKED_BY_ENFORCEMENT' "
          f"WHERE execution_id='{child}' AND step_id='readback';")
    test(json.loads(query(verify)).get("code")=="RULE_CHILD_REQUIRED_STEPS_NOT_CLEAN",
         "ONE_BAD_CHILD_STEP_BLOCKS_RECEIPT")
    query(f"UPDATE public.lf_operation_execution_steps SET status='PASS_CLEAN' "
          f"WHERE execution_id='{child}' AND step_id='readback';")
    query(f"UPDATE lf_ops.reglas SET descripcion='External drift not in child' WHERE codigo='{RULE}';")
    test(json.loads(query(verify)).get("code")=="RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT",
         "CANONICAL_ROW_DRIFT_BLOCKS_RECEIPT")
    dr=invoke(packet)
    test(dr.get("effect_verified") is False and
         dr.get("child_receipt",{}).get("code")=="RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT" and
         dr.get("next_action")=="VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE",
         "REPLAY_AFTER_DRIFT_FAILS_CLOSED")
    test(query("SELECT count(*) FROM public.lf_skill_invocation_v1")=="1",
         "FAILED_READBACK_DOES_NOT_DUPLICATE_SKILL")
    print(json.dumps({"status":"ISOLATED_PG17_RULE_RECEIPT_PASS",
        "actual_skill_invoker_executed":True,"actual_candidate_writer_executed":True,
        "actual_canonical_steps":7,"model_called":False,"parent_fixture_synthetic":True,
        "production_write":False,"promoted":False,
        "dynamic_screen_hardcoded":False}),flush=True)

if __name__=="__main__":
    main()
