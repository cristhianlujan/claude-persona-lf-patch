#!/usr/bin/env python3
"""LF #3774, isolated PostgreSQL 17 candidate create, negative, rollback, and readback."""
import json,os,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
D=ROOT/"sandbox/lf_contract_gate_test/db_write_transport"
LINK=ROOT/"sandbox/lf_contract_gate_test/product_rule_link_child_v1"
HERE=Path(__file__).resolve().parent
CONTAINER=os.environ.get("PG_CONTAINER","")
PARENT="EXEC-PROFILE-GATE2-PG17RULECREATE01"
RULE="TEST-RULE-CREATE-001"
SPEC={"change_kind":"CREATE_CANDIDATE","rule_code":RULE,"category":"AUTH",
      "title":"Control aprobado de acceso",
      "description":"Control funcional aprobado en fuente de decisión sintética",
      "reason":"Materializar definición validada sin promoción",
      "config":{"test":True,"max_retries":0},
      "transversal":False,"source_decision_ref":"supabase://public.lf_decisiones_gov/101",
      "screen_code":"B2B-AUTH-001"}
INPUT={"regla_codigo":RULE,"target_type":"REGLA","target_code":RULE,
       "decision_id":"PG17-CREATE-001","candidate_create":SPEC}

def query(sql,failed=False):
    assert CONTAINER, "ISOLATED_PG17_DOCKER_REQUIRED"
    p=subprocess.run(["docker","exec","-i",CONTAINER,"psql","-X","-A","-t","-q",
                      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                     input=sql,text=True,capture_output=True,timeout=75)
    if failed:
        assert p.returncode!=0,"FAIL_SQL_SHOULD_FAIL"
        return p.stderr
    if p.returncode:raise AssertionError("PG17_SQL_FAILURE:"+p.stderr[-1900:])
    return p.stdout.strip()
def check(k,value):
    assert value,"FAIL_"+k
    print("PASS_"+k,flush=True)
def load(path):
    check("SOURCE_"+path.name,path.is_file())
    query(path.read_text(encoding="utf-8"))
def invoke(data=INPUT,parent=PARENT):
    raw=json.dumps(data,sort_keys=True).replace("'","''")
    return json.loads(query(f"SELECT public.lf_skill_invoke_v1('RULE_CREATE_APPLY','{parent}','{raw}'::jsonb);"))
def count_rule():
    return int(query(f"SELECT count(*) FROM lf_ops.reglas WHERE codigo='{RULE}';"))
def count_child():
    return int(query("SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='CREACION_REGLA_LF';"))
def receipt(parent,run,child):
    return json.loads(query(f"SELECT public.lf_skill_rule_create_child_readback_v1('{parent}','{run}','{child}');"))

def main():
    check("PG_CONTAINER_PRESENT",bool(CONTAINER))
    for path in [
        D/"lf_rule_child_pg17_original_source_fixture_v1.sql",
        D/"lf_rule_child_pg17_seed_v1.sql",
        ROOT/"supabase/migrations/20261109092529_lf_profile_rule_update_child_execution_v1.sql",
        ROOT/"supabase/migrations/20261109093901_lf_profile_rule_child_verified_return_v1.sql",
        LINK/"lf_link_source_fixture_v1.sql",
        LINK/"lf_link_seed_pg17.sql",
        ROOT/"supabase/migrations/20261110130000_lf_product_rule_link_child_v1.sql",
        HERE/"lf_create_handler_pg17.sql",
        HERE/"lf_create_seed_pg17.sql",
        ROOT/"supabase/migrations/20261110150000_lf_product_rule_create_child_v1.sql"
    ]:load(path)
    check("OPENER_BOUND",query("SELECT opener_fn FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_CREATE_APPLY';")=="lf_skill_o_rule_create_v1")
    for role in ("anon","authenticated"):
        check("OPENER_DENY_"+role,query(
          "SELECT has_function_privilege('"+role+"','public.lf_skill_o_rule_create_v1(text,jsonb,text,text,text)','EXECUTE');")=="f")
    check("OPENER_SERVICE_ROLE",query(
      "SELECT has_function_privilege('service_role','public.lf_skill_o_rule_create_v1(text,jsonb,text,text,text)','EXECUTE');")=="t")
    check("ABSENT_BEFORE",count_rule()==0 and count_child()==0)

    encoded=json.dumps(INPUT,sort_keys=True).replace("'","''")
    tx=query(f"BEGIN;SELECT public.lf_skill_invoke_v1('RULE_CREATE_APPLY','{PARENT}','{encoded}'::jsonb);ROLLBACK;")
    check("TRANSACTION_TEST_EXECUTED",'"effect_verified": true' in tx or '"effect_verified":true' in tx)
    check("ROLLBACK_ZERO_RESIDUE",count_rule()==0 and count_child()==0)
    check("ROLLBACK_NO_SKILL_RUN",query(
      "SELECT count(*) FROM public.lf_skill_invocation_v1 WHERE skill_code='RULE_CREATE_APPLY';")=="0")

    result=invoke()
    check("CREATE_COMPLETED",result.get("status")=="COMPLETED")
    check("CREATE_EFFECT_VERIFIED",result.get("effect_verified") is True)
    child=result["child_execution_id"];run=result["skill_run_id"]
    check("CANONICAL_RECEIPT",result.get("child_receipt",{}).get("status")=="APPLIED_VERIFIED")
    check("ONLY_ONE_CANDIDATE",count_rule()==1)
    check("CANDIDATE_NOT_VIGENTE",query(
      f"SELECT estado||':'||pendiente_decision::text FROM lf_ops.reglas WHERE codigo='{RULE}';")=="CANDIDATO:true")
    check("NO_LINK_CREATED",query(
      "SELECT count(*) FROM lf_ops.reglas_pantallas rp JOIN lf_ops.reglas r ON r.id=rp.regla_id "
      f"WHERE r.codigo='{RULE}';")=="0")
    check("SEVEN_CORE_STEPS",query(
      f"SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id='{child}' AND status='PASS_CLEAN';")=="7")
    check("CHILD_CLOSED",query(
      f"SELECT status FROM public.lf_operation_execution WHERE execution_id='{child}';")=="COMPLETED")
    check("PARENT_STILL_OPEN",query(
      f"SELECT status FROM public.lf_operation_execution WHERE execution_id='{PARENT}';")=="IN_PROGRESS")
    check("RECEIPT_FRESH",receipt(PARENT,run,child).get("effect_verified") is True)

    again=invoke()
    check("REPLAY_SAME_CHILD",again.get("replay") is True and again.get("child_execution_id")==child)
    check("REPLAY_VERIFIED",again.get("effect_verified") is True)
    check("REPLAY_ONE_ROW",count_rule()==1 and count_child()==1)

    fake=dict(INPUT);fake["candidate_create"]=dict(SPEC,description="Changed without product decision")
    wrong=invoke(fake)
    check("FORGED_CANDIDATE_BLOCKED",wrong.get("status") in ("BLOCKED","FAILED"))
    check("FORGED_CANDIDATE_NO_EFFECT",count_child()==1 and count_rule()==1)

    other="EXEC-PROFILE-GATE2-PG17RULECREATE02"
    query("INSERT INTO public.lf_operation_execution("
          "execution_id,operation_code,target_type,target_code,status,request_sha256,manifest,created_by_execution_id)"
          f" SELECT '{other}',operation_code,target_type,target_code,status,request_sha256,manifest,'ISOLATED_PG17'"
          f" FROM public.lf_operation_execution WHERE execution_id='{PARENT}';")
    query("INSERT INTO public.lf_operation_execution_steps("
          "execution_id,step_order,step_id,status,evidence_ref,evidence_payload)"
          f" SELECT '{other}',step_order,step_id,status,evidence_ref,evidence_payload"
          f" FROM public.lf_operation_execution_steps WHERE execution_id='{PARENT}';")
    duplicate=invoke(parent=other)
    check("DUPLICATE_BLOCKED",duplicate.get("status") in ("BLOCKED","FAILED"))
    check("DUPLICATE_ZERO_NEW_CHILD",count_child()==1 and count_rule()==1)

    sql=f"UPDATE lf_ops.reglas SET descripcion='FALSIFIED' WHERE codigo='{RULE}';"
    query(sql)
    check("READBACK_TAMPERING_REJECTED",
          receipt(PARENT,run,child).get("code")=="CREATE_RECEIPT_CANONICAL_DRIFT")
    query(f"UPDATE lf_ops.reglas SET descripcion='{SPEC['description']}' WHERE codigo='{RULE}';")
    check("READBACK_RESTORED",receipt(PARENT,run,child).get("status")=="APPLIED_VERIFIED")

    check("NO_PRETEND_PROMOTION",query(f"SELECT estado FROM lf_ops.reglas WHERE codigo='{RULE}';")=="CANDIDATO")
    print("LF_RULE_CREATE_PG17_CANONICAL_POSITIVE_NEGATIVE_ROLLBACK_PASS",flush=True)

if __name__=="__main__":main()
