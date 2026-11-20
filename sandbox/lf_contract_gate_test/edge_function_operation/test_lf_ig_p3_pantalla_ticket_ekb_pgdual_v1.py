"""P3 real migration on PG17.6/18.7 fixture: ticket-bound screen, negatives and rollback.

The two target procedures are shape-reduced fixtures, NOT a claim of production E2E.
"""
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGRATION_MATCHES=sorted((ROOT/"supabase/migrations").glob("*_lf_ig_p3_screen_ticket_and_ekb_v1.sql"))
if len(MIGRATION_MATCHES)!=1:
 raise RuntimeError("LF_P3_MIGRATION_SOURCE_NOT_UNIQUE_OR_MISSING")
SQL=MIGRATION_MATCHES[0]
EKB=r"""
CREATE TABLE public.lf_error_knowledge(
  id uuid,codigo text,categoria text,titulo text,descripcion text,causa_raiz text,
  patron text,prevencion text,validacion text,severidad text,frecuencia integer,
  primera_vez timestamptz,ultima_vez timestamptz,lote_origen text,pr text,
  estado text,evidencia text,lifecycle_phase text,consumer_role text[],
  root_cause_family text,detectability text,source_context text,source_ref text,
  created_at timestamptz,updated_at timestamptz
);
"""
FUNCTIONS=r"""
CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(
 p_execution_id text,p_skill_code text,p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
 v_req jsonb:=jsonb_build_object('runtime_slug','input-governance-agent-v1',
  'request_body',jsonb_build_object('pantalla_id',51,'consumer','CONTEXT_PACK'));
 v_exp timestamptz:=now();
 v_screen integer:=51;
 v_id uuid:=gen_random_uuid();
BEGIN
 RETURN jsonb_build_object('status','AUTHORIZED','ticket',v_id::text,
   'execution_id',p_execution_id,'skill_code',p_skill_code,
   'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport','DIRECT_EDGE_INVOCATION');
END $f$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
 p_execution_id text,p_source_revision text,p_source_digest text,p_actor_execution_id text
) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
 v_skill_code text:=p_source_revision;
 v_ig_ticket jsonb;
BEGIN
 v_ig_ticket:=public.lf_profile_skill_runtime_ticket_issue_v1(
   p_execution_id,v_skill_code,'{}'::jsonb);
 RETURN jsonb_build_object(
   'request_body',jsonb_build_object(
                'action','profile_skill_runtime_v1','execution_id',p_execution_id,
                'skill_code',v_skill_code),
              'terminal_statuses',jsonb_build_array('READY'));
END $f$;
"""
RUN=r"""
BEGIN;
SELECT 'SCREEN_TICKET='||coalesce(
 public.lf_profile_skill_runtime_ticket_issue_v1(
 'RUN-TEST','INPUT_GOVERNANCE_CONTEXT_PACK','{}'::jsonb)->>'pantalla_id','NULL');
SELECT 'SCREEN_BRIDGE='||coalesce(
 public.lf_profile_native_bridge_prepare_v1(
 'RUN-TEST','INPUT_GOVERNANCE_CONTEXT_PACK','digest','actor')
 #>>'{request_body,pantalla_id}','NULL');
SELECT 'UNRELATED_UNCHANGED='||(
 NOT (public.lf_profile_native_bridge_prepare_v1(
 'RUN-TEST','UNRELATED_READ_ONLY_SKILL','digest','actor')->'request_body' ? 'pantalla_id'))::text;
SELECT 'EKB_COUNT='||count(*) FROM public.lf_error_knowledge;
SELECT 'EKB_ACTIVE='||count(*) FROM public.lf_error_knowledge
 WHERE estado='ACTIVO' AND pr='#TEST_PR'
 AND consumer_role=ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[]
 AND evidencia='prueba en memoria, sin corrida real';
ROLLBACK;
SELECT 'EKB_NO_RESIDUE='||count(*) FROM public.lf_error_knowledge;
"""

class P3TicketPGDual(unittest.TestCase):
 def test_pantalla_ticket_source_bound_pg17_pg18(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=SQL.read_text(encoding="utf-8")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-p3-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-1400:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(q,fail=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=q,capture_output=True,text=True,timeout=180)
      if fail:self.assertNotEqual(p.returncode,0,"EXPECTED_NEGATIVE_FAIL")
      else:self.assertEqual(p.returncode,0,p.stderr[-4000:]+"\n"+p.stdout[-2400:])
      return p.stdout,p.stderr
     sql(EKB+FUNCTIONS)
     # First reject a target without the exact preimage: migration must fail atomically.
     broken=FUNCTIONS.replace("'runtime_slug',v_req->>'runtime_slug',\n   'expires_at'",
       "'runtime_slug',v_req->>'runtime_slug',\n   'changed_preimage',true,\n   'expires_at'")
     sql(broken)
     _,err=sql(migration,fail=True)
     self.assertIn("LF_P3_TICKET_SCREEN_TRANSPORT_PATCH_NOT_APPLIED",err)
     sql(FUNCTIONS)
     # Do not commit the positive fixture: use BEGIN/ROLLBACK; migration outer transaction
     # is rolled back with the test body on the same psql session.
     fixture=migration.replace("BEGIN;\nDO $screen_patch$",
       "BEGIN;\nDO $screen_patch$",1)
     out,err=sql(re.sub(r"v_pr text:='#[^']+';", "v_pr text:='#TEST_PR';",fixture)
                 .replace("COMMIT;\n","",1)+RUN)
     for k in (
       "SCREEN_TICKET=51","SCREEN_BRIDGE=51","UNRELATED_UNCHANGED=true",
       "EKB_COUNT=4","EKB_ACTIVE=4","EKB_NO_RESIDUE=0"):
      self.assertIn(k,out,k+"\n"+out[-3500:])
     print("PASS_P3_TICKET_PG"+pg+"_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
