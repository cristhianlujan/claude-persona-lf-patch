"""E20: exact LIVE function preimages; PG17.6 / PG18.7, BEGIN/ROLLBACK."""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
FIX=(Path(__file__).parent/"fixtures/lf_e20_handoff_preimage_20261116.sql").read_text(encoding="utf-8")
MATCHES=list((ROOT/"supabase/migrations").glob("*_lf_e20_repair_promotion_allowed_handoff_v1.sql"))
assert len(MATCHES)==1,"E20_MIGRATION_NAME_AMBIGUOUS"
MIG=MATCHES[0].read_text(encoding="utf-8")
BODY=MIG.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]
SETUP=r"""
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_activos (
 codigo_activo text PRIMARY KEY,tipo_activo text,archived_at timestamptz,metadata jsonb
);
CREATE TABLE public.lf_profile_selection_registry_v1 (
 profile_code text,descriptor_status text
);
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,manifest jsonb,operation_code text,status text,target_code text
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text,step_id text,status text,evidence_payload jsonb,
 PRIMARY KEY(execution_id,step_id)
);
CREATE FUNCTION public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"VALID","router_resume_allowed":true}'::jsonb $$;
CREATE FUNCTION public.lf_router_semantic_action_binding_validate_v1(jsonb,text,text)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('valid',true,'candidate_action_code','PROFILE_EXECUTION',
  'operation_code','EJECUCION_PERFIL_LF','binding_sha256',repeat('c',64)) $$;
CREATE FUNCTION public.lf_router_repair_profile_code_v1()
RETURNS text LANGUAGE sql AS $$ SELECT 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'::text $$;
CREATE FUNCTION public.lf_router_resolve_v1(text,text,text,text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.lf_operation_revision_sha256_v1(text)
RETURNS text LANGUAGE sql AS $$ SELECT repeat('a',64) $$;
CREATE FUNCTION public.lf_profile_execution_executor_admission_v1(text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"admitted":true}'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $stub$
BEGIN
 INSERT INTO public.lf_operation_execution(execution_id,manifest,operation_code,status,target_code)
 VALUES ($1,$8,'EJECUCION_PERFIL_LF','IN_PROGRESS',$5);
 RETURN jsonb_build_object('status','READY','execution_id',$1);
END $stub$;
CREATE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
RETURNS jsonb LANGUAGE plpgsql AS $stub$
BEGIN
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$4);
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
END $stub$;
INSERT INTO public.lf_activos VALUES
 ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PERFIL',NULL,
  '{"profile_slug":"systemic_root_cause_repair_lf","canonical_profile_key":"srcr"}'),
 ('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL',NULL,
  '{"profile_slug":"product_director_lf","canonical_profile_key":"product_director"}');
INSERT INTO public.lf_profile_selection_registry_v1 VALUES
 ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','CURRENT'),('PERFIL-PRODUCT-DIRECTOR-LF','CURRENT');
"""
ASSERTS=r"""
DO $scenario$
DECLARE req jsonb; result jsonb; h jsonb; v jsonb; b jsonb; m jsonb; lit text;
BEGIN
  result:=jsonb_build_object('decision','RESOLVED',
        'semantic_receipt_sha256',repeat('d',64),
        'positive_target_refs',jsonb_build_array('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'));
  lit:='Audita, modifica y promociona las reglas de login B2B';
  req:=jsonb_build_object('literal_request',lit,
       'request_sha256',encode(extensions.digest(convert_to(lit,'UTF8'),'sha256'),'hex'),
       'router_action_binding',jsonb_build_object(
         'profile_task_intent','REPAIR_MISSING_PRODUCT_STRUCTURE'));
  h:=public.lf_router_profile_execution_handoff_v1(
       req,result,'PROGRAMACION','LF','{"target_type":"PANTALLA","target_hint":"login B2B"}'::jsonb);
  IF h->>'status'<>'READY' OR h#>>'{handoff,repair_execution_authority,promotion_allowed}'<>'true'
   THEN RAISE EXCEPTION 'E20_GOVERNED_REPAIR_NOT_ALLOWED:%',h; END IF;
  v:=public.lf_router_profile_execution_handoff_validate_v1(
      h->'handoff',lit,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
  IF v->>'valid'<>'true' OR v->>'promotion_allowed'<>'true'
   THEN RAISE EXCEPTION 'E20_VALIDATOR_NOT_TRUE:%',v; END IF;
  b:=public.lf_profile_execution_begin_from_handoff_v1(
      h->'handoff','GPT_NATIVE','E20-GOV','key-GOV','ACT-OWNER','repo/test','path/test','{}'::jsonb);
  SELECT manifest INTO m FROM public.lf_operation_execution WHERE execution_id='E20-GOV';
  IF b->>'status'<>'READY' OR m->>'promotion_allowed'<>'true'
    OR m->>'governed_repair_write'<>'true' OR m->>'no_promotion'<>'false'
   THEN RAISE EXCEPTION 'E20_BEGIN_GOV_INVALID:% %',b,m; END IF;
  -- No owner promotion authorization: explicit negative request always false.
  lit:='Audita, modifica y no promocionar las reglas del login B2B';
  req:=jsonb_build_object('literal_request',lit,
       'request_sha256',encode(extensions.digest(convert_to(lit,'UTF8'),'sha256'),'hex'),
       'router_action_binding',jsonb_build_object(
         'profile_task_intent','REPAIR_MISSING_PRODUCT_STRUCTURE'));
  h:=public.lf_router_profile_execution_handoff_v1(
       req,result,'PROGRAMACION','LF','{"target_type":"PANTALLA"}'::jsonb);
  IF h#>>'{handoff,repair_execution_authority,promotion_allowed}'<>'false'
   THEN RAISE EXCEPTION 'E20_NEGATIVE_OWNER_INTENT_BYPASSED:%',h; END IF;
  v:=public.lf_router_profile_execution_handoff_validate_v1(
      h->'handoff',lit,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
  IF v->>'valid'<>'true' OR v->>'promotion_allowed'<>'false'
   THEN RAISE EXCEPTION 'E20_NEGATIVE_VALIDATOR_INVALID:%',v; END IF;

  -- A READ_ONLY profile cannot acquire promotion authority even with same literal.
  lit:='Audita, modifica y promociona las reglas de login B2B';
  result:=jsonb_build_object('decision','RESOLVED',
       'semantic_receipt_sha256',repeat('d',64),
       'positive_target_refs',jsonb_build_array('PERFIL-PRODUCT-DIRECTOR-LF'));
  req:=jsonb_build_object('literal_request',lit,
       'request_sha256',encode(extensions.digest(convert_to(lit,'UTF8'),'sha256'),'hex'),
       'router_action_binding',jsonb_build_object('profile_task_intent','ANALYZE'));
  h:=public.lf_router_profile_execution_handoff_v1(req,result,'PRODUCTO','LF',NULL);
  IF h->>'status'<>'READY' OR h->'handoff'->'repair_execution_authority'<>'null'::jsonb
    AND h->'handoff'->'repair_execution_authority' IS NOT NULL
   THEN RAISE EXCEPTION 'E20_RO_AUTH_NOT_NULL:%',h; END IF;
  v:=public.lf_router_profile_execution_handoff_validate_v1(
       h->'handoff',lit,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF v->>'valid'<>'true' OR v->>'promotion_allowed'<>'false'
   THEN RAISE EXCEPTION 'E20_RO_VALIDATOR_INVALID:%',v; END IF;
  b:=public.lf_profile_execution_begin_from_handoff_v1(
      h->'handoff','GPT_NATIVE','E20-RO','key-RO','ACT-OWNER','repo/test','path/test','{}'::jsonb);
  SELECT manifest INTO m FROM public.lf_operation_execution WHERE execution_id='E20-RO';
  IF b->>'status'<>'READY' OR m->>'promotion_allowed'<>'false'
     OR m->>'governed_repair_write'<>'false'
   THEN RAISE EXCEPTION 'E20_BEGIN_READ_ONLY_INVALID:% %',b,m; END IF;
END $scenario$;
SELECT 'GOV='||(manifest->>'promotion_allowed') FROM public.lf_operation_execution WHERE execution_id='E20-GOV';
SELECT 'RO='||(manifest->>'promotion_allowed') FROM public.lf_operation_execution WHERE execution_id='E20-RO';
"""

class E20DualRollback(unittest.TestCase):
    def test_e20_live_source_positive_negative_rollback(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        for version in ("17.6","18.7"):
            with self.subTest(version=version):
                cname="lf-e20-"+uuid.uuid4().hex[:10]
                run=subprocess.run(["docker","run","-d","--rm","--name",cname,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                    text=True,capture_output=True,timeout=180)
                self.assertEqual(run.returncode,0,run.stderr)
                try:
                    for _ in range(90):
                        status=subprocess.run(["docker","exec",cname,"pg_isready","-U","postgres"],
                            text=True,capture_output=True,timeout=12)
                        if status.returncode==0:
                            logs=subprocess.run(["docker","logs",cname],
                                text=True,capture_output=True,timeout=12)
                            if "PostgreSQL init process complete; ready for start up." in (
                                logs.stdout+logs.stderr): break
                        time.sleep(.5)
                    self.assertEqual(status.returncode,0,"PG_NOT_READY")
                    def execute(sql,fail=False):
                        p=subprocess.run(["docker","exec","-i",cname,"psql",
                            "-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                            input=sql,text=True,capture_output=True,timeout=180)
                        if fail:self.assertNotEqual(p.returncode,0,p.stdout[-1500:])
                        else:self.assertEqual(p.returncode,0,p.stderr[-4000:]+"\n"+p.stdout[-3500:])
                        return p.stdout,p.stderr
                    # Reject source drift, don't patch guessed definitions.
                    neg="""CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_v1(
                      p_request jsonb,p_result jsonb,p_channel text,p_business text,
                      p_scope jsonb DEFAULT NULL::jsonb)
                      RETURNS jsonb LANGUAGE sql AS $drift$ SELECT '{}'::jsonb $drift$;"""
                    out,err=execute("BEGIN;\n"+SETUP+FIX+neg+"\n"+BODY+"ROLLBACK;",fail=True)
                    self.assertIn("E20_SOURCE_STATE_DRIFT:handoff_builder",err)
                    out,err=execute("BEGIN;\n"+SETUP+FIX+BODY+ASSERTS+
                        "\nROLLBACK;\nSELECT 'RESIDUE='||(to_regclass('public.lf_operation_execution') IS NULL);\n")
                    for expected in ("GOV=true","RO=false","RESIDUE=true"):
                        self.assertIn(expected,out,expected+"\n"+out[-2500:])
                    print("PASS_E20_OWNER_PROMOTION_ROUTER_HANDOFF_PG"+version+"_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",cname],capture_output=True,timeout=30)

if __name__=="__main__":
    unittest.main()
