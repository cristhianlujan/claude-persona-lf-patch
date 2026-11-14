"""#3887: use the actual main SQL definitions, validate opener/finding isolation PG17/PG18.

Sandbox only. No Supabase connection, no external APIs, and no direct production writes.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OPENER_SOURCE = ROOT / "supabase/migrations/20261104190000_lf_skill_child_context_v1.sql"
INVOKER_SOURCE = ROOT / "supabase/migrations/20261114105801_lf_profile_skill_step40_policy_v1.sql"


def exact_source_function(path, name):
    sql = path.read_text(encoding="utf-8")
    marker = "CREATE OR REPLACE FUNCTION public." + name + "("
    pos = sql.rfind(marker)
    if pos < 0:
        raise AssertionError("OFFICIAL_FUNCTION_SOURCE_MISSING:" + name)
    end = sql.find("end $function$;", pos)
    if end < 0:
        end = sql.find("END;\n$function$;", pos)
        if end < 0:
            raise AssertionError("OFFICIAL_FUNCTION_SOURCE_UNTERMINATED:" + name)
        return sql[pos:end + len("END;\n$function$;")]
    return sql[pos:end + len("end $function$;")]


BASE = r"""
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_operation_execution (
  execution_id text PRIMARY KEY,target_code text,operation_code text,
  status text,manifest jsonb
);
CREATE TABLE public.lf_activos (
  codigo_activo text,tipo_activo text,ruta_esperada text,archived_at timestamptz
);
CREATE TABLE public.lf_profile_write_authority_v1 (
  profile_code text,operation_code text,status text,self_update_allowed boolean
);
CREATE TABLE public.lf_profile_self_update_approval_v1 (
  approval_id integer,profile_code text,target_code text,target_path text,
  request_sha256 text,status text,created_at timestamptz,used_at timestamptz
);
CREATE FUNCTION public.lf_profile_family_v1(text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT $1 $$;
CREATE FUNCTION public.lf_skill_child_caller_manifest_v1(text) RETURNS jsonb
LANGUAGE sql STABLE AS $$ SELECT
 '{"governed_caller_method":"GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1",
 "caller_repository":"cristhianlujan/claude-persona-lf-patch",
 "caller_workflow_ref":"fixture://profile-update"}'::jsonb $$;
CREATE FUNCTION public.lf_router_governed_caller_route_v1(jsonb,text,text)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT CASE WHEN $2='PERFIL-BLOCKED-LF' THEN
 '{"status":"BLOCKED","blocking_code":"ROUTER_DENIED"}'::jsonb
 ELSE jsonb_build_object('status','ROUTER_REDERIVED','caller_code','FIXTURE_OIDC',
 'downstream_execution_allowed',false,'semantic_receipt_sha256',repeat('a',64),
 'semantic_request',jsonb_build_object('source','fixture'),
 'router_result',jsonb_build_object('status','READY_TO_EXECUTE',
 'operation_code','ACTUALIZACION_PERFIL_LF','action_code','PROFILE_UPDATE')) END $$;
CREATE FUNCTION public.lf_profile_update_begin_v1(
 text,text,text,text,text,text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT
 jsonb_build_object('status','CHILD_PREPARED_NO_WRITE','manifest',$8,
 'parent',$7,'target',$2) $$;
INSERT INTO public.lf_operation_execution(execution_id,target_code,operation_code,status)
 VALUES('PARENT-1','PERFIL-ROOT-LF','EJECUCION_PERFIL_LF','IN_PROGRESS');
INSERT INTO public.lf_activos(codigo_activo,tipo_activo,ruta_esperada)
 VALUES('PERFIL-OTHER-LF','PERFIL','profiles/other_lf'),
 ('PERFIL-BLOCKED-LF','PERFIL','profiles/blocked_lf');
"""

INVOKER_SETUP = r"""
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,target_code text,status text,
 operation_code text,manifest jsonb);
CREATE TABLE public.lf_skill_selector_policy_v1(
 profile_code text,skill_code text,required_operation text,
 enabled boolean,channels text[],applicability_contract jsonb);
CREATE TABLE public.lf_profile_skill_selection_receipt_v1(
 skill_run_id text PRIMARY KEY,parent_execution_id text,skill_code text,
 profile_code text,channel text,selection_mode text,
 selection_evidence jsonb,selection_sha256 text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb);
CREATE FUNCTION public.lf_profile_execution_plan_v1(text,text,jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"status":"READY","skills":[
 {"skill_code":"INPUT_GOVERNANCE_CONTEXT_PACK","required_operation":"EJECUCION_PERFIL_LF",
  "selection_mode":"DETERMINISTIC_POLICY","selection_evidence":{"from":"current"}},
 {"skill_code":"SCREEN_RULES_SNAPSHOT","required_operation":"EJECUCION_PERFIL_LF",
  "selection_mode":"SEMANTIC_OPTIONAL","selection_evidence":{"from":"current"}}
 ]}'::jsonb $$;
CREATE FUNCTION public.lf_skill_invoke_v1(text,text,jsonb) RETURNS jsonb
 LANGUAGE sql AS $$ SELECT CASE WHEN $1='INPUT_GOVERNANCE_CONTEXT_PACK'
 THEN '{"status":"BLOCKED","blocking_code":"IG_BLOCKED_FINDING"}'::jsonb
 ELSE '{"status":"COMPLETED","skill_run_id":"RUN-SNAPSHOT-1","output":{"n_reglas":71}}'::jsonb END $$;
INSERT INTO public.lf_operation_execution VALUES(
 'PARENT-1','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS','EJECUCION_PERFIL_LF',
 '{"router_profile_handoff":{"channel":"PRODUCTO"}}');
INSERT INTO public.lf_skill_selector_policy_v1 VALUES
 ('PERFIL-PRODUCT-DIRECTOR-LF','INPUT_GOVERNANCE_CONTEXT_PACK',
  'EJECUCION_PERFIL_LF',true,ARRAY['PRODUCTO'],'{"only_if_applicable":false}'),
 ('PERFIL-PRODUCT-DIRECTOR-LF','SCREEN_RULES_SNAPSHOT',
  'EJECUCION_PERFIL_LF',true,ARRAY['PRODUCTO'],'{"only_if_applicable":false}');
"""


class SkillRuntimePgDual(unittest.TestCase):
    def test_exact_opener_and_finding_isolation(self):
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED")
        opener=exact_source_function(OPENER_SOURCE, "lf_skill_o_profile_update_v1")
        invoker=exact_source_function(INVOKER_SOURCE, "lf_profile_skill_invoke_selected_v1")
        self.assertIn("SKILL_TRUSTED_CONTEXT_MISSING",opener)
        self.assertIn("SELF_UPDATE_REQUIRES_HUMAN_APPROVAL",opener)
        self.assertIn("SKILL_ROUTER_UPDATE_NOT_AUTHORIZED",opener)
        self.assertIn("SKILL_FAILED_AS_FINDING",invoker)
        self.assertIn("CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS",invoker)

        valid={
          "target_code":"PERFIL-OTHER-LF",
          "target_path":"profiles/other_lf/SKILL.md",
          "_trusted":{"main_sha":"a"*40,"target_blob_sha":"b"*40,
           "caller":{"run_id":"123","workflow_sha":"c"*40}}
        }
        for tag in ("17.6","18.7"):
            with self.subTest(pg=tag):
                name="lf-skill-opener-"+uuid.uuid4().hex[:12]
                p=subprocess.run(["docker","run","-d","--rm","--name",name,
                                  "-e","POSTGRES_PASSWORD=fixture-only",
                                  "postgres:"+tag],
                                 capture_output=True,text=True,timeout=180)
                self.assertEqual(p.returncode,0,p.stderr)
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready",
                                              "-U","postgres"],capture_output=True,timeout=10)
                        if ready.returncode==0: break
                        time.sleep(1)
                    self.assertEqual(ready.returncode,0)
                    def run_sql(sql,good=True):
                        r=subprocess.run(["docker","exec","-i",name,"psql",
                              "-X","-A","-t","-U","postgres","-d","postgres",
                              "-v","ON_ERROR_STOP=1"],input=sql,text=True,
                              capture_output=True,timeout=120)
                        if good: self.assertEqual(r.returncode,0,r.stderr[-2500:])
                        else: self.assertNotEqual(r.returncode,0,r.stdout)
                        return r
                    run_sql(BASE+"\n"+opener)
                    missing={k:v for k,v in valid.items() if k!="_trusted"}
                    call=lambda payload: (
                      "SELECT public.lf_skill_o_profile_update_v1("
                      "'CHILD-1',"+ "'" + json.dumps(payload,ensure_ascii=False).replace("'","''") +
                      "'::jsonb,'PARENT-1','RUN-1','"+"d"*64+"');"
                    )
                    no_trust=run_sql(call(missing),False)
                    self.assertIn("SKILL_TRUSTED_CONTEXT_MISSING",no_trust.stderr)
                    outside={**valid,"target_path":"profiles/another/SKILL.md"}
                    out=run_sql(call(outside),False)
                    self.assertIn("SKILL_TARGET_NOT_OWNED_BY_PROFILE",out.stderr)
                    denied={**valid,"target_code":"PERFIL-BLOCKED-LF",
                            "target_path":"profiles/blocked_lf/SKILL.md"}
                    no_router=run_sql(call(denied),False)
                    self.assertIn("SKILL_ROUTER_UPDATE_NOT_AUTHORIZED",no_router.stderr)
                    ok=run_sql(call(valid))
                    obj=json.loads(ok.stdout.strip().splitlines()[-1])
                    self.assertEqual(obj["status"],"CHILD_PREPARED_NO_WRITE")
                    self.assertEqual(obj["manifest"]["profile_handoff"]["skill_run_id"],"RUN-1")
                    self.assertEqual(obj["manifest"]["github_write_executed"],False)
                    self.assertEqual(obj["manifest"]["production_authorized"],False)
                    self.assertEqual(obj["manifest"]["router_semantic_receipt_sha256"],"a"*64)

                    run_sql(INVOKER_SETUP+"\n"+invoker)
                    ig=run_sql("SELECT public.lf_profile_skill_invoke_selected_v1("
                      "'PARENT-1','PRODUCTO','INPUT_GOVERNANCE_CONTEXT_PACK','{}'::jsonb,NULL);")
                    finding=json.loads(ig.stdout.strip().splitlines()[-1])
                    self.assertEqual(finding["status"],"SKILL_FAILED_AS_FINDING")
                    self.assertEqual(finding["blocking_code"],"IG_BLOCKED_FINDING")
                    self.assertEqual(finding["next_action"],
                                     "CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS")
                    other=run_sql("SELECT public.lf_profile_skill_invoke_selected_v1("
                      "'PARENT-1','PRODUCTO','SCREEN_RULES_SNAPSHOT','{}'::jsonb,NULL);")
                    success=json.loads(other.stdout.strip().splitlines()[-1])
                    self.assertEqual(success["status"],"COMPLETED")
                    receipt=run_sql("SELECT count(*) FROM "
                      "public.lf_profile_skill_selection_receipt_v1;")
                    self.assertEqual(receipt.stdout.strip(),"1")
                    print("PASS_SKILL_OPENER_AND_ISOLATION_PG"+tag+
                          " deny_missing_trust deny_outside_scope deny_router "+
                          "governed_child_prepared IG_BLOCKED_AS_FINDING "+
                          "SCREEN_COMPLETED receipt=1 no_live_write")
                finally:
                    subprocess.run(["docker","rm","-f",name],
                                   capture_output=True,timeout=30)
