"""PG17/18 executable regression: selected IG skill ticket is bound to SAME parent RUN.

Runs in disposable Docker Postgres, never connects to Supabase production.
Before patch: live function must return SKILL_TICKET_POLICY_NOT_CURRENT (0 consumptions).
After patch (BEGIN/ROLLBACK): selected RUN consumes the generic + legacy tickets
exactly once; unselected, closed, expired and replayed tickets are rejected.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261120070000_lf_ig_ticket_parent_run_plan_v1.sql"
PREIMAGE_MD5="507ce5b8edcdd993ccb3ea978220ecea"
LIVE_FUNCTION=r"""CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_consume_v1(p_ticket uuid, p_execution_id text, p_skill_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
 v_r private.lf_profile_skill_runtime_ticket_v1%rowtype;
 v_old jsonb;v_plan jsonb;v_profile text;v_channel text;
BEGIN
 SELECT e.target_code,e.manifest#>>'{router_profile_handoff,channel}'
 INTO v_profile,v_channel FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
  AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF v_profile IS NULL THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_PARENT_NOT_ACTIVE'); END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_profile,v_channel,NULL);
 IF v_plan->>'status'<>'READY' OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_POLICY_NOT_CURRENT'); END IF;
 UPDATE private.lf_profile_skill_runtime_ticket_v1 r
 SET consumed_at=clock_timestamp(),consumed_by='LF_PROFILES_GOVERNANCE_CALLER_V1'
 WHERE r.ticket_id=p_ticket AND r.execution_id=p_execution_id
   AND r.skill_code=p_skill_code AND r.consumed_at IS NULL
   AND r.expires_at>clock_timestamp()
 RETURNING r.* INTO v_r;
 IF NOT FOUND THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_EXPIRED_INVALID_OR_REPLAY'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1 c
   WHERE c.skill_code=v_r.skill_code AND c.status='READY'
     AND c.effect='READ_ONLY' AND c.runtime_slug=v_r.runtime_slug)
 THEN RAISE EXCEPTION 'SKILL_RUNTIME_CATALOG_SOURCE_DRIFT'; END IF;
 IF v_r.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND v_r.request_body->>'consumer'='CONTEXT_PACK' THEN
   v_old:=public.lf_profile_input_governance_runtime_ticket_consume_v1(
     p_ticket,p_execution_id,(v_r.request_body->>'pantalla_id')::integer,'CONTEXT_PACK');
   IF coalesce((v_old->>'authorized')::boolean,false) IS NOT TRUE THEN
     RAISE EXCEPTION 'SKILL_LEGACY_IG_TICKET_NOT_AUTHORIZED';
   END IF;
 END IF;
 RETURN jsonb_build_object('authorized',true,
   'execution_id',v_r.execution_id,'skill_code',v_r.skill_code,
   'runtime_slug',v_r.runtime_slug,'request_body',v_r.request_body,
   'expires_at',v_r.expires_at);
END
$function$
"""

SETUP=r"""
CREATE SCHEMA private;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, operation_code text NOT NULL,
 target_type text NOT NULL,target_code text NOT NULL,status text NOT NULL,
 manifest jsonb NOT NULL
);
CREATE TABLE private.lf_profile_skill_runtime_ticket_v1(
 ticket_id uuid PRIMARY KEY,execution_id text NOT NULL,skill_code text NOT NULL,
 runtime_slug text NOT NULL,request_body jsonb NOT NULL,
 issued_at timestamptz DEFAULT now(),expires_at timestamptz NOT NULL,
 consumed_at timestamptz,consumed_by text
);
CREATE TABLE private.lf_profile_input_governance_runtime_ticket_v1(
 ticket_id uuid PRIMARY KEY,execution_id text NOT NULL,pantalla_id integer NOT NULL,
 consumer text NOT NULL,expires_at timestamptz NOT NULL,
 consumed_at timestamptz,consumed_by text
);
CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text PRIMARY KEY,status text NOT NULL,effect text NOT NULL,
 runtime_slug text NOT NULL
);
INSERT INTO public.lf_skill_catalog_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','READY','READ_ONLY','input-governance-agent-v1');

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(
 p_profile_code text,p_channel text DEFAULT NULL,p_semantic_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE
AS $base$ SELECT jsonb_build_object('status','READY','skills','[]'::jsonb) $base$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
 p_execution_id text,p_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE
AS $run$
 SELECT CASE WHEN e.status='IN_PROGRESS'
 THEN jsonb_build_object('status','READY',
   'skills',CASE WHEN coalesce(e.manifest->'skill_selection_decision',p_decision)
     ->'selected_skill_codes' @> '["INPUT_GOVERNANCE_CONTEXT_PACK"]'::jsonb
   THEN jsonb_build_array(jsonb_build_object(
     'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK','effect','READ_ONLY'))
   ELSE '[]'::jsonb END)
 ELSE jsonb_build_object('status','BLOCKED','skills','[]'::jsonb) END
 FROM public.lf_operation_execution e WHERE e.execution_id=p_execution_id
$run$;

CREATE OR REPLACE FUNCTION public.lf_profile_input_governance_runtime_ticket_consume_v1(
 p_ticket uuid,p_execution_id text,p_pantalla_id integer,p_consumer text)
RETURNS jsonb LANGUAGE plpgsql AS $legacy$
DECLARE did boolean:=false;
BEGIN
 UPDATE private.lf_profile_input_governance_runtime_ticket_v1
 SET consumed_at=clock_timestamp(),consumed_by='TEST'
 WHERE ticket_id=p_ticket AND execution_id=p_execution_id
   AND pantalla_id=p_pantalla_id AND consumer=p_consumer
   AND consumed_at IS NULL AND expires_at>clock_timestamp();
 did:=FOUND;
 RETURN jsonb_build_object('authorized',did);
END
$legacy$;

INSERT INTO public.lf_operation_execution
SELECT id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-UI-ARCHITECT',st,
  jsonb_build_object('router_profile_handoff',jsonb_build_object('channel','PRODUCTO'))
  ||CASE WHEN selected THEN jsonb_build_object('skill_selection_decision',
     jsonb_build_object('selected_skill_codes',
       jsonb_build_array('INPUT_GOVERNANCE_CONTEXT_PACK'),
       'reason','Exact profile-scoped input governance E2E')) ELSE '{}'::jsonb END
FROM (VALUES
 ('RUN-SELECTED','IN_PROGRESS',true),
 ('RUN-UNSELECTED','IN_PROGRESS',false),
 ('RUN-CLOSED','COMPLETED',true),
 ('RUN-EXPIRED','IN_PROGRESS',true)
) v(id,st,selected);

INSERT INTO private.lf_profile_skill_runtime_ticket_v1
(ticket_id,execution_id,skill_code,runtime_slug,request_body,expires_at)
SELECT ('11111111-1111-4111-8111-'||lpad(n::text,12,'0'))::uuid,id,
 'INPUT_GOVERNANCE_CONTEXT_PACK','input-governance-agent-v1',
 jsonb_build_object('consumer','CONTEXT_PACK','pantalla_id',52),
 CASE WHEN id='RUN-EXPIRED' THEN now()-interval '1 minute'
      ELSE now()+interval '5 minutes' END
FROM (VALUES (1,'RUN-SELECTED'),(2,'RUN-UNSELECTED'),
             (3,'RUN-CLOSED'),(4,'RUN-EXPIRED')) v(n,id);
INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1
(ticket_id,execution_id,pantalla_id,consumer,expires_at)
SELECT ticket_id,execution_id,52,'CONTEXT_PACK',expires_at
FROM private.lf_profile_skill_runtime_ticket_v1;
"""

PREPATCH=r"""
DO $pre$
DECLARE out jsonb;
BEGIN
 out:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000001'::uuid,
   'RUN-SELECTED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF out->>'code' IS DISTINCT FROM 'SKILL_TICKET_POLICY_NOT_CURRENT' THEN
   RAISE EXCEPTION 'PREPATCH_REPRODUCTION_FAILED:%',out;
 END IF;
 IF EXISTS(SELECT 1 FROM private.lf_profile_skill_runtime_ticket_v1
   WHERE consumed_at IS NOT NULL) THEN RAISE EXCEPTION 'PREPATCH_CONSUMED'; END IF;
 RAISE NOTICE 'PASS_PREPATCH_REPRODUCED_OPTIONAL_SKILL_403';
END $pre$;
"""

CHECKS=r"""
DO $test$
DECLARE v jsonb;
BEGIN
 v:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000001'::uuid,
   'RUN-SELECTED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF v->>'authorized' IS DISTINCT FROM 'true'
    OR v->>'skill_code' IS DISTINCT FROM 'INPUT_GOVERNANCE_CONTEXT_PACK'
    OR v->>'runtime_slug' IS DISTINCT FROM 'input-governance-agent-v1'
    OR (v->'request_body'->>'pantalla_id') IS DISTINCT FROM '52'
 THEN RAISE EXCEPTION 'SELECTED_SKILL_NOT_AUTHORIZED:%',v; END IF;
 IF (SELECT count(*) FROM private.lf_profile_skill_runtime_ticket_v1
      WHERE execution_id='RUN-SELECTED' AND consumed_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM private.lf_profile_input_governance_runtime_ticket_v1
      WHERE execution_id='RUN-SELECTED' AND consumed_at IS NOT NULL)<>1
 THEN RAISE EXCEPTION 'DUAL_TICKET_CONSUMPTION_NOT_1_TO_1'; END IF;
 RAISE NOTICE 'PASS_SELECTED_IG_SKILL_DUAL_CONSUME_ONCE';

 v:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000001'::uuid,
   'RUN-SELECTED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF v->>'code' IS DISTINCT FROM 'SKILL_TICKET_EXPIRED_INVALID_OR_REPLAY'
 THEN RAISE EXCEPTION 'REPLAY_NOT_REJECTED:%',v; END IF;

 v:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000002'::uuid,
   'RUN-UNSELECTED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF v->>'code' IS DISTINCT FROM 'SKILL_TICKET_POLICY_NOT_CURRENT'
 THEN RAISE EXCEPTION 'UNSELECTED_NOT_REJECTED:%',v; END IF;

 v:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000003'::uuid,
   'RUN-CLOSED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF v->>'code' IS DISTINCT FROM 'SKILL_TICKET_PARENT_NOT_ACTIVE'
 THEN RAISE EXCEPTION 'CLOSED_RUN_NOT_REJECTED:%',v; END IF;

 v:=public.lf_profile_skill_runtime_ticket_consume_v1(
   '11111111-1111-4111-8111-000000000004'::uuid,
   'RUN-EXPIRED','INPUT_GOVERNANCE_CONTEXT_PACK');
 IF v->>'code' IS DISTINCT FROM 'SKILL_TICKET_EXPIRED_INVALID_OR_REPLAY'
 THEN RAISE EXCEPTION 'EXPIRED_NOT_REJECTED:%',v; END IF;

 IF (SELECT count(*) FROM private.lf_profile_skill_runtime_ticket_v1
     WHERE consumed_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM private.lf_profile_input_governance_runtime_ticket_v1
     WHERE consumed_at IS NOT NULL)<>1
 THEN RAISE EXCEPTION 'NEGATIVE_TEST_CONSUMED_EXTRA_TICKETS'; END IF;

 IF NOT (SELECT prosecdef FROM pg_proc
   WHERE oid='public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)'::regprocedure)
 THEN RAISE EXCEPTION 'SECURITY_DEFINER_LOST'; END IF;
 RAISE NOTICE 'PASS_REPLAY_UNSELECTED_CLOSED_EXPIRED_AND_SECURITY_DEFINER';
END $test$;
"""

class TestIgTicketParentPlanPgDual(unittest.TestCase):
 def check(self,image,version):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_UNAVAILABLE")
  name="lf-ig-parent-ticket-"+uuid.uuid4().hex[:10]
  started=subprocess.run(
    ["docker","run","--rm","-d","--name",name,
     "-e","POSTGRES_PASSWORD=postgres",image],
    text=True,capture_output=True,timeout=180)
  self.assertEqual(started.returncode,0,started.stderr[-2200:])
  try:
   for _ in range(100):
    p=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
      text=True,capture_output=True,timeout=8)
    if p.returncode==0: break
    time.sleep(.75)
   else: self.fail("POSTGRES_NOT_READY")
   def sql(src):
    p=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=src,text=True,capture_output=True,timeout=120)
    self.assertEqual(p.returncode,0,p.stderr[-7000:])
    return p.stdout.strip(),p.stderr

   self.assertTrue(sql("SHOW server_version_num;")[0].startswith(version))
   sql(SETUP+"\n"+LIVE_FUNCTION+"\n")
   before=sql("SELECT md5(pg_get_functiondef("
    "'public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)'::regprocedure));")[0]
   self.assertRegex(before,r"^[0-9a-f]{32}$")
   self.assertIn("PASS_PREPATCH_REPRODUCED_OPTIONAL_SKILL_403",sql(PREPATCH)[1])

   src=MIGRATION.read_text(encoding="utf-8")
   self.assertEqual(src.count(PREIMAGE_MD5),1)
   self.assertIn("lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb)",src)
   self.assertIn("SOURCE_STATE_DRIFT",src)
   # Fixture PostgreSQL version may normalize pg_get_functiondef differently;
   # replace the guard hash ONLY in the isolated test transaction.
   src=src.replace(PREIMAGE_MD5,before,1)
   body=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
   result,logs=sql("BEGIN;\n"+body+"\n"+CHECKS+"\nROLLBACK;\n"+
     "SELECT CASE WHEN md5(pg_get_functiondef("+
     "'public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)'::regprocedure))='"+
     before+"' AND (SELECT count(*) FROM private.lf_profile_skill_runtime_ticket_v1 "+
     "WHERE consumed_at IS NOT NULL)=0 THEN 'PASS_ROLLBACK' "+
     "ELSE 'ROLLBACK_FAILED' END;")
   self.assertEqual(result.splitlines()[-1],"PASS_ROLLBACK")
   for marker in ("PASS_SELECTED_IG_SKILL_DUAL_CONSUME_ONCE",
                  "PASS_REPLAY_UNSELECTED_CLOSED_EXPIRED_AND_SECURITY_DEFINER"):
    self.assertIn(marker,logs)
   print("PASS_LF_IG_TICKET_PARENT_PLAN_"+image.replace(":","_"),flush=True)
  finally:
   subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=60)

 def test_pg17(self): self.check("postgres:17.6","170006")
 def test_pg18(self): self.check("postgres:18.7","180007")

if __name__=="__main__": unittest.main()
