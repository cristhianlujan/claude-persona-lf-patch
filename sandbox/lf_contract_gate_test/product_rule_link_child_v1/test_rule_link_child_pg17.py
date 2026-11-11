#!/usr/bin/env python3
"""LF #3774: real SQL inside ephemeral PostgreSQL 17, synthetic-only evidence.

No access to live Supabase, external keys or a real GPT inference. The only
purpose is to test deterministic authorization, materialization, rollback
and the canonical receipt against frozen source definitions.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
D=ROOT/"sandbox/lf_contract_gate_test/db_write_transport"
HERE=Path(__file__).resolve().parent
PG=os.environ.get("PG_CONTAINER","")
PARENT="EXEC-PROFILE-GATE2-PG17RULELINK01"
RULE="TEST-RULE-LINK-001"
SCREEN=51

def sql(query, *, fail=False):
    if not PG:
        raise RuntimeError("PG17_DOCKER_CONTAINER_REQUIRED")
    p=subprocess.run(
        ["docker","exec","-i",PG,"psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1",
         "-U","postgres","-d","postgres"],
        input=query,capture_output=True,text=True,timeout=75,
    )
    if fail:
        if p.returncode == 0:
            raise AssertionError("FAIL_EXPECTED_SQL_EXCEPTION")
        return p.stderr
    if p.returncode:
        raise AssertionError("FAIL_PG17_SQL:"+p.stderr[-2500:])
    return p.stdout.strip()

def check(code,condition):
    if not condition: raise AssertionError("FAIL_"+code)
    print("PASS_"+code,flush=True)

def stage(path):
    check("FIXTURE_"+path.name,path.is_file())
    sql(path.read_text(encoding="utf-8"))

def packet(**overrides):
    value={
      "regla_codigo":RULE,
      "pantalla_id":SCREEN,
      "target_type":"REGLA_PANTALLA_RELATION",
      "target_code":f"{RULE}@{SCREEN}",
      "decision_id":"PG17-LINK-001",
      "analysis_snapshot_sha256":sql(
          "SELECT public.lf_asset_snapshot_sha_v1('REGLA','TEST-RULE-LINK-001');"),
      "link_intent":{"change_kind":"LINK_EXISTING_RULE","rule_code":RULE,
                     "screen_code":"B2B-AUTH-001"}
    }
    value.update(overrides)
    return value

def invoke(data,parent=PARENT):
    literal=json.dumps(data,ensure_ascii=False,sort_keys=True).replace("'","''")
    raw=sql(f"SELECT public.lf_skill_invoke_v1('RULE_LINK_APPLY','{parent}',"
            f"'{literal}'::jsonb);")
    return json.loads(raw)

def receipt(parent,run,child):
    return json.loads(sql(f"SELECT public.lf_skill_rule_link_child_readback_v1("
                         f"'{parent}','{run}','{child}');"))

def count_child():
    return int(sql("SELECT count(*) FROM public.lf_operation_execution "
                   "WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';"))

def count_relation():
    return int(sql("SELECT count(*) FROM lf_ops.reglas_pantallas rp "
                   "JOIN lf_ops.reglas r ON r.id=rp.regla_id "
                   f"WHERE r.codigo='{RULE}' AND rp.pantalla_id=51;"))

def expect_block(case,data,code,parent=PARENT):
    before=count_child()
    result=invoke(data,parent=parent)
    check(case+"_BLOCKED",result.get("status") in {"BLOCKED","FAILED"})
    check(case+"_NO_NEW_CHILD",count_child()==before)
    check(case+"_EVIDENCE",code in json.dumps(result,sort_keys=True))

def main():
    check("ISOLATED_PG17_CONTAINER",bool(PG))
    stage(D/"lf_rule_child_pg17_original_source_fixture_v1.sql")
    stage(D/"lf_rule_child_pg17_seed_v1.sql")
    stage(ROOT/"supabase/migrations/20261109092529_lf_profile_rule_update_child_execution_v1.sql")
    stage(ROOT/"supabase/migrations/20261109093901_lf_profile_rule_child_verified_return_v1.sql")
    stage(HERE/"lf_link_source_fixture_v1.sql")
    stage(HERE/"lf_link_seed_pg17.sql")
    check("BASE_INVOKER_PARITY",
          sql("SELECT md5(pg_get_functiondef("
              "'public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure));")
          =="ac7e351e1834cbfb91aabf26e1a04a8d")
    check("LINK_HELPER_PARITY",
          sql("SELECT md5(pg_get_functiondef("
              "'public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure));")
          =="915f9be58ad48c8a839316b7a65fb561")
    stage(ROOT/"supabase/migrations/20261110130000_lf_product_rule_link_child_v1.sql")
    check("SKILL_OPENER_BOUND",
          sql("SELECT opener_fn FROM public.lf_skill_catalog_v1 "
              "WHERE skill_code='RULE_LINK_APPLY';")=="lf_skill_o_rule_link_v1")
    for role in ("anon","authenticated"):
        check("DENY_"+role.upper(),
              sql("SELECT has_function_privilege("
                  f"'{role}','public.lf_skill_o_rule_link_v1(text,jsonb,text,text,text)',"
                  "'EXECUTE');")=="f")
    check("ALLOW_SERVICE_ROLE",
          sql("SELECT has_function_privilege('service_role',"
              "'public.lf_skill_o_rule_link_v1(text,jsonb,text,text,text)',"
              "'EXECUTE');")=="t")
    orig=packet()
    check("INITIAL_RELATION_ABSENT",count_relation()==0)

    # A true transaction abort must remove both the effect and the receipt.
    txn=json.dumps(orig,ensure_ascii=False,sort_keys=True).replace("'","''")
    raw=sql("BEGIN; SELECT public.lf_skill_invoke_v1('RULE_LINK_APPLY',"
            f"'{PARENT}','{txn}'::jsonb); ROLLBACK;")
    check("ROLLBACK_INVOKE_SUCCESS",'"effect_verified": true' in raw
          or '"effect_verified":true' in raw)
    check("ROLLBACK_NO_RELATION",count_relation()==0)
    check("ROLLBACK_NO_CHILD",count_child()==0)
    check("ROLLBACK_NO_INVOCATION",
          sql("SELECT count(*) FROM public.lf_skill_invocation_v1 "
              "WHERE skill_code='RULE_LINK_APPLY';")=="0")

    positive=invoke(orig)
    check("POSITIVE_STATUS",positive.get("status")=="COMPLETED")
    check("POSITIVE_EFFECT",positive.get("effect_verified") is True)
    check("POSITIVE_RECEIPT",
          positive.get("child_receipt",{}).get("status")=="APPLIED_VERIFIED")
    child=positive.get("child_execution_id")
    run=positive.get("skill_run_id")
    check("PARENT_STAYS_OPEN",
          sql(f"SELECT status FROM public.lf_operation_execution WHERE execution_id='{PARENT}';")
          =="IN_PROGRESS")
    check("CHILD_COMPLETED",
          sql(f"SELECT status FROM public.lf_operation_execution WHERE execution_id='{child}';")
          =="COMPLETED")
    check("FIVE_REGISTERED_PASS_STEPS",
          sql("SELECT count(*) FROM public.lf_operation_execution_steps "
              f"WHERE execution_id='{child}' AND status='PASS_CLEAN';")=="5")
    check("EXACTLY_ONE_RELATION",count_relation()==1)
    check("CANONICAL_RULE_UNCHANGED",
          sql(f"SELECT estado||':'||pendiente_decision::text FROM lf_ops.reglas "
              f"WHERE codigo='{RULE}';")=="VIGENTE:false")
    check("CANONICAL_RECEIPT_VERIFIED",
          receipt(PARENT,run,child).get("effect_verified") is True)
    replay=invoke(orig)
    check("REPLAY_SAME_CHILD",
          replay.get("replay") is True
          and replay.get("child_execution_id")==child
          and replay.get("skill_run_id")==run)
    check("REPLAY_EFFECT_VERIFIED",replay.get("effect_verified") is True)
    check("REPLAY_NO_DUPLICATE_CHILD",count_child()==1)
    check("REPLAY_NO_DUPLICATE_RELATION",count_relation()==1)

    # Existing production link is now idempotent on replay, but new matched
    # parent case can also exercise helper ALREADY_EXISTS; that case must
    # not mutate the established link.
    sql("INSERT INTO public.lf_operation_execution("
        "execution_id,operation_code,target_type,target_code,status,request_sha256,"
        "manifest,created_by_execution_id) "
        "SELECT 'EXEC-PROFILE-GATE2-PG17RULELINK02',operation_code,"
        "target_type,target_code,status,request_sha256,manifest,'ISOLATED_PG17' "
        f"FROM public.lf_operation_execution WHERE execution_id='{PARENT}';")
    sql("INSERT INTO public.lf_operation_execution_steps("
        "execution_id,step_order,step_id,status,evidence_ref,evidence_payload) "
        "SELECT 'EXEC-PROFILE-GATE2-PG17RULELINK02',step_order,step_id,"
        "status,evidence_ref,evidence_payload "
        f"FROM public.lf_operation_execution_steps WHERE execution_id='{PARENT}';")
    already=invoke(orig,parent="EXEC-PROFILE-GATE2-PG17RULELINK02")
    check("ALREADY_EXISTS_IDEMPOTENT",
          already.get("effect_verified") is True)
    check("ALREADY_EXISTS_SINGLE_RELATION",count_relation()==1)
    check("ALREADY_EXISTS_TWO_CHILDREN",count_child()==2)

    expect_block("STALE_SNAPSHOT",packet(analysis_snapshot_sha256="0"*64),
                 "LINK_CHILD_STALE_RULE")
    expect_block("FORGED_LINK_INTENT",packet(
        link_intent={"change_kind":"LINK_EXISTING_RULE",
                     "rule_code":RULE,"screen_code":"SOME_FORGED_SCREEN"}),
                 "LINK_CHILD_SCREEN_SCOPE")

    sql("UPDATE public.lf_profile_write_authority_v1 SET status='RETIRED' "
        "WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';")
    noauth=invoke(orig)
    check("AUTH_REVOKE_BLOCKED",noauth.get("blocking_code")=="SKILL_NOT_AUTHORIZED_FOR_PROFILE")
    sql("UPDATE public.lf_profile_write_authority_v1 SET status='ACTIVE' "
        "WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';")

    # First test the prospective new parent. The forged judge must not
    # create a child, even though a different parent's link already exists.
    sql("INSERT INTO public.lf_operation_execution("
        "execution_id,operation_code,target_type,target_code,status,request_sha256,"
        "manifest,created_by_execution_id) "
        "SELECT 'EXEC-PROFILE-GATE2-PG17JUDGEFAIL01',operation_code,"
        "target_type,target_code,status,request_sha256,manifest,'ISOLATED_PG17' "
        f"FROM public.lf_operation_execution WHERE execution_id='{PARENT}';")
    sql("INSERT INTO public.lf_operation_execution_steps("
        "execution_id,step_order,step_id,status,evidence_ref,evidence_payload) "
        "SELECT 'EXEC-PROFILE-GATE2-PG17JUDGEFAIL01',step_order,step_id,"
        "status,evidence_ref,evidence_payload "
        f"FROM public.lf_operation_execution_steps WHERE execution_id='{PARENT}';")
    sql("UPDATE public.lf_operation_execution_steps "
        "SET evidence_payload=jsonb_set(evidence_payload,"
        "'{semantic_judge_result,status}','\"FAIL\"'::jsonb) "
        "WHERE execution_id='EXEC-PROFILE-GATE2-PG17JUDGEFAIL01' "
        "AND step_id='semantic_judge';")
    expect_block("JUDGE_FAIL",orig,"LINK_CHILD_JUDGE_NOT_CLEAN",
                 parent="EXEC-PROFILE-GATE2-PG17JUDGEFAIL01")

    sql("UPDATE lf_ops.reglas SET estado='CANDIDATO' "
        f"WHERE codigo='{RULE}';")
    expect_block("CANDIDATE_RULE",packet(),"LINK_CHILD_RULE_NOT_VIGENTE")
    sql("UPDATE lf_ops.reglas SET estado='VIGENTE' "
        f"WHERE codigo='{RULE}';")

    before=receipt(PARENT,run,child)
    check("RECEIPT_PRE_FALSIFY",before.get("status")=="APPLIED_VERIFIED")
    sql("UPDATE lf_ops.reglas_pantallas SET nota='FORGED' "
        f"WHERE regla_id=436 AND pantalla_id={SCREEN};")
    check("RECEIPT_FALSIFICATION_BLOCKS",
          receipt(PARENT,run,child).get("code")=="LINK_RECEIPT_CANONICAL_DRIFT")
    sql("UPDATE lf_ops.reglas_pantallas SET nota=NULL "
        f"WHERE regla_id=436 AND pantalla_id={SCREEN};")
    check("RECEIPT_RECOVERS_ON_EXACT_STATE",
          receipt(PARENT,run,child).get("status")=="APPLIED_VERIFIED")
    print("LF_PRODUCT_RULE_LINK_PG17_POSITIVE_NEGATIVE_ROLLBACK_PASS",flush=True)

if __name__=="__main__":
    main()
