"""CHAT F: disposable PG17/18 source-pinned migration, 4 paths, transactional ROLLBACK.
Never connects to real Supabase or replays historical execution IDs.
The fixture substitutes the four expected live hashes only inside the in-memory
test copy, retaining the exact checked hashes in the committed migration.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261114235500_lf_profile_skill_late_step40_reconciliation_v1.sql"
EXPECTED=[
 ("public.lf_profile_native_bridge_prepare_v1(text,text,text,text)","be58d7c3167964e9639df7c5f2a0ae7d"),
 ("public.lf_profile_execution_plan_for_run_v1(text,jsonb)","2dd5b6570e5a4b5cc08b2905ef2dae57"),
 ("public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)","5518b63ac3a1707ffeda5989a9f1d5c4"),
 ("public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)","353a555c6c3a1666d36293dd6792ea9a"),
]
FIXTURE=r"""
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $r$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $r$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, operation_code text NOT NULL, target_type text NOT NULL,
 target_code text NOT NULL, status text NOT NULL, manifest jsonb NOT NULL);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text, step_id text, status text, evidence_payload jsonb,
 created_at timestamptz DEFAULT clock_timestamp(),
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_operation_step_contracts(
 operation_code text, step_order int, step_id text, status text, resolver_ref text);
INSERT INTO public.lf_operation_step_contracts VALUES(
 'EJECUCION_PERFIL_LF',40,'input_validate','ACTIVE_ENFORCEMENT',
 'public.lf_profile_execution_input_validate_v1');
CREATE TABLE public.lf_skill_invocation_v1(
 skill_run_id text PRIMARY KEY,parent_execution_id text,skill_code text,status text);
CREATE TABLE public.lf_profile_skill_selection_receipt_v1(
 skill_run_id text PRIMARY KEY,parent_execution_id text,skill_code text);
CREATE TABLE public.test_skill_behavior(
 execution_id text PRIMARY KEY, outcome text NOT NULL);

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(
 p_profile_code text,p_channel text,p_decision jsonb,p_ctx jsonb)
RETURNS jsonb LANGUAGE sql STABLE
AS $selector$
 SELECT jsonb_build_object('status','READY','skills','[]'::jsonb,
   'content_findings',CASE WHEN p_decision IS NULL THEN
     jsonb_build_array(jsonb_build_object(
       'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
       'continuation_allowed',true,'remediation_action','SUBMIT_SKILL_SELECTION'))
    ELSE '[]'::jsonb END)
$selector$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
 p_execution_id text,p_decision jsonb DEFAULT NULL::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE
AS $plan$
DECLARE d jsonb;
BEGIN
 SELECT coalesce(manifest->'skill_selection_decision',p_decision) INTO d
 FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 RETURN jsonb_build_object('status','READY',
   'skills',CASE WHEN d->'selected_skill_codes' ? 'INPUT_GOVERNANCE_CONTEXT_PACK'
     THEN jsonb_build_array(jsonb_build_object(
       'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK','effect','READ_ONLY',
       'selection_mode','SEMANTIC_DESCRIPTOR'))
     ELSE '[]'::jsonb END,
   'selection_receipt',jsonb_build_object('run_id',p_execution_id),
   'content_findings',CASE WHEN d IS NULL THEN
      jsonb_build_array(jsonb_build_object(
        'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
        'remediation_action','SUBMIT_SKILL_SELECTION'))
      ELSE '[]'::jsonb END);
END
$plan$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(
 p_execution_id text,p_channel text,p_skill_code text,p_input jsonb,
 p_semantic_decision jsonb DEFAULT NULL::jsonb)
RETURNS jsonb LANGUAGE plpgsql
AS $invoke$
DECLARE b text; r text;
BEGIN
 SELECT outcome INTO b FROM public.test_skill_behavior WHERE execution_id=p_execution_id;
 IF b='FAILED' THEN
   RETURN jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'blocking_code','TEST_SKILL_HANDLER_FAILURE','skill_code',p_skill_code);
 END IF;
 IF b='RUNTIME_REQUIRED' THEN
   RETURN jsonb_build_object('status','RUNTIME_REQUIRED','skill_code',p_skill_code);
 END IF;
 r:='TEST-SKILLRUN-'||p_execution_id;
 INSERT INTO public.lf_skill_invocation_v1
 VALUES(r,p_execution_id,p_skill_code,'COMPLETED') ON CONFLICT DO NOTHING;
 INSERT INTO public.lf_profile_skill_selection_receipt_v1
 VALUES(r,p_execution_id,p_skill_code) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('status','COMPLETED','skill_run_id',r,
   'skill_code',p_skill_code,'evidence_ref','test://skill/'||r);
END
$invoke$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(
 p_execution_id text,p_skill_code text,p_input jsonb)
RETURNS jsonb LANGUAGE sql
AS $ticket$
 SELECT jsonb_build_object('status','BLOCKED','code','TEST_RUNTIME_TICKET_DENIED');
$ticket$;

-- Deliberately minimal bridge preimage with the same exact patch anchors.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
 p_execution_id text,p_source_revision text,p_source_digest text,
 p_actor_execution_id text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_skill_ig jsonb;
  v_skill_plan jsonb;
  v_skill_findings jsonb:='[]'::jsonb;
  v_skill_receipts jsonb:='[]'::jsonb;
  v_input jsonb;
  v_context jsonb;
  v_handoff jsonb;
  v_skill jsonb;
  v_result jsonb;
  v_code text;
BEGIN
  SELECT manifest->'router_profile_handoff' INTO v_handoff
  FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id
    AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_input IS NULL THEN
    v_input:=jsonb_build_object('status','READY','resolved_scope',
       jsonb_build_object('resolved_screen_code','B2B-CARGA-002'),
       'input_governance','{}'::jsonb);
    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
    FOR v_skill IN SELECT value FROM jsonb_array_elements(v_skill_plan->'skills') LOOP
      v_code:=v_skill->>'skill_code';
      v_result:=public.lf_profile_skill_invoke_selected_v1(
         p_execution_id,v_handoff->>'channel',v_code,
         jsonb_build_object('execution_id',p_execution_id,
           'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
           'request_text',v_handoff->>'literal_request',
           'scope',v_input->'resolved_scope','consumer','CONTEXT_PACK'),NULL);
      v_skill_receipts:=v_skill_receipts||jsonb_build_array(
        jsonb_build_object('skill_code',v_code,'result',v_result));
      IF v_result->>'status'<>'COMPLETED' THEN
        v_skill_findings:=v_skill_findings||jsonb_build_array(
          jsonb_build_object('skill_code',v_code,'status','SKILL_FAILED_AS_FINDING',
             'blocking_code',v_result->>'blocking_code','continuation_allowed',true));
      END IF;
    END LOOP;
    v_input:=v_input||jsonb_build_object(
       'skill_execution_receipts',v_skill_receipts,'skill_findings',v_skill_findings);
    INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
    VALUES(p_execution_id,'input_validate','STEP_PASS_WITH_EVIDENCE',v_input);
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='context_admission';

  RETURN jsonb_build_object('status','NATIVE_MODEL_INPUT_READY',
    'input_governance',v_input->'input_governance',
    'step40_skill_findings',v_input->'skill_findings',
    'next_step','execute_profile');
END
$function$;
"""
CHECKS=r"""
DO $test$
DECLARE v jsonb; step40 jsonb; first_payload jsonb;
 skill_decision jsonb:=jsonb_build_object(
   'selected_skill_codes',jsonb_build_array('INPUT_GOVERNANCE_CONTEXT_PACK'),
   'reason','Governed semantic selection','review_mode','CURRENT_CONTEXT_REVIEW');
BEGIN
 INSERT INTO public.lf_operation_execution
 SELECT id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
    'IN_PROGRESS',jsonb_build_object('router_profile_handoff',
       jsonb_build_object('channel','PRODUCTO','literal_request','Revisar carga masiva B2B'))
 FROM unnest(ARRAY['TEST-F-NONE','TEST-F-SKILL','TEST-F-FAILED','TEST-F-LATE']) id;

 INSERT INTO public.test_skill_behavior VALUES
  ('TEST-F-NONE','COMPLETED'),('TEST-F-SKILL','COMPLETED'),
  ('TEST-F-FAILED','FAILED'),('TEST-F-LATE','COMPLETED');

 -- 1. NO SKILL: PASS, selector finding preserved; no invocation.
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-NONE',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 SELECT evidence_payload INTO step40 FROM public.lf_operation_execution_steps
 WHERE execution_id='TEST-F-NONE' AND step_id='input_validate';
 IF v->>'status'<>'NATIVE_MODEL_INPUT_READY'
   OR step40#>>'{skill_findings,0,finding_code}'<>'SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED'
   OR (SELECT count(*) FROM public.lf_skill_invocation_v1
       WHERE parent_execution_id='TEST-F-NONE')<>0 THEN
   RAISE EXCEPTION 'FAIL_NONE:%:%',v,step40; END IF;
 RAISE NOTICE 'PASS_STEP40_NO_SKILL_AND_SELECTOR_CONTENT_FINDING';

 -- 2. SKILL selected BEFORE Step40: canonical invocation + preserved PASS.
 UPDATE public.lf_operation_execution SET manifest=manifest||
   jsonb_build_object('skill_selection_decision',skill_decision)
 WHERE execution_id='TEST-F-SKILL';
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-SKILL',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 SELECT evidence_payload INTO step40 FROM public.lf_operation_execution_steps
 WHERE execution_id='TEST-F-SKILL' AND step_id='input_validate';
 IF v->>'status'<>'NATIVE_MODEL_INPUT_READY'
   OR jsonb_array_length(step40->'skill_execution_receipts')<>1
   OR (SELECT count(*) FROM public.lf_skill_invocation_v1
       WHERE parent_execution_id='TEST-F-SKILL')<>1
   OR (SELECT count(*) FROM public.lf_profile_skill_late_receipt_v1
       WHERE parent_execution_id='TEST-F-SKILL')<>0 THEN
   RAISE EXCEPTION 'FAIL_SELECTED:%:%',v,step40; END IF;
 RAISE NOTICE 'PASS_STEP40_SELECTED_SKILL_CANONICAL_RECEIPT';

 -- 3. Failed skill is a finding, not a Step40 block.
 UPDATE public.lf_operation_execution SET manifest=manifest||
   jsonb_build_object('skill_selection_decision',skill_decision)
 WHERE execution_id='TEST-F-FAILED';
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-FAILED',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 SELECT evidence_payload INTO step40 FROM public.lf_operation_execution_steps
 WHERE execution_id='TEST-F-FAILED' AND step_id='input_validate';
 IF v->>'status'<>'NATIVE_MODEL_INPUT_READY'
   OR step40#>>'{skill_findings,0,status}'<>'SKILL_FAILED_AS_FINDING'
   OR (SELECT status FROM public.lf_operation_execution_steps
       WHERE execution_id='TEST-F-FAILED' AND step_id='input_validate')
         <>'STEP_PASS_WITH_EVIDENCE' THEN
   RAISE EXCEPTION 'FAIL_FAILED_SKILL:%:%',v,step40; END IF;
 RAISE NOTICE 'PASS_FAILED_SKILL_IS_FINDING_STEP40_PASS';

 -- 4. LATE decision: Step40 PASS first, then decision, then invocation before Step50.
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-LATE',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 SELECT evidence_payload INTO first_payload FROM public.lf_operation_execution_steps
 WHERE execution_id='TEST-F-LATE' AND step_id='input_validate';
 IF jsonb_array_length(first_payload->'skill_execution_receipts')<>0 THEN
   RAISE EXCEPTION 'FAIL_LATE_FIXTURE_PRECONDITION'; END IF;
 UPDATE public.lf_operation_execution SET manifest=manifest||
   jsonb_build_object('skill_selection_decision',skill_decision)
 WHERE execution_id='TEST-F-LATE';
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-LATE',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 SELECT evidence_payload INTO step40 FROM public.lf_operation_execution_steps
 WHERE execution_id='TEST-F-LATE' AND step_id='input_validate';
 IF v->>'status'<>'NATIVE_MODEL_INPUT_READY'
    OR v#>>'{late_skill_findings,0,finding_code}'<>'SKILL_SELECTION_LATE'
    OR jsonb_array_length(v->'late_skill_execution_receipts')<>1
    OR step40<>first_payload
    OR (SELECT count(*) FROM public.lf_profile_skill_late_receipt_v1
        WHERE parent_execution_id='TEST-F-LATE' AND receipt_kind='TERMINAL')<>1
    OR (SELECT count(*) FROM public.lf_skill_invocation_v1
        WHERE parent_execution_id='TEST-F-LATE')<>1
    OR (SELECT count(*) FROM public.lf_profile_skill_selection_receipt_v1
        WHERE parent_execution_id='TEST-F-LATE')<>1 THEN
    RAISE EXCEPTION 'FAIL_LATE_SELECTION:%:%',v,step40; END IF;
 v:=public.lf_profile_native_bridge_prepare_v1('TEST-F-LATE',repeat('a',40),'sha256:'||repeat('a',64),NULL);
 IF v#>>'{late_skill_execution_receipts,0,replay}'<>'true'
    OR (SELECT count(*) FROM public.lf_skill_invocation_v1
        WHERE parent_execution_id='TEST-F-LATE')<>1 THEN
    RAISE EXCEPTION 'FAIL_LATE_REPLAY:%',v; END IF;
 RAISE NOTICE 'PASS_LATE_SKILL_INVOKED_ONCE_READBACK_AND_HISTORICAL_PASS_IMMUTABLE';
END $test$;
"""
class TestLateSkillPgDualRollback(unittest.TestCase):
 def check(self,image,version):
  self.assertTrue(shutil.which("docker"),"DOCKER_UNAVAILABLE")
  name="lf-late-selection-"+uuid.uuid4().hex[:10]
  r=subprocess.run(["docker","run","--rm","-d","--name",name,
    "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=180)
  self.assertEqual(r.returncode,0,r.stderr[-3000:])
  try:
   for _ in range(110):
    probe=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
      capture_output=True,text=True,timeout=8)
    if probe.returncode==0:
      logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=8)
      if "PostgreSQL init process complete; ready for start up." in logs.stdout+logs.stderr:break
    time.sleep(.7)
   else:self.fail("PG_NOT_READY")
   def sql(cmd):
    result=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
      "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
      input=cmd,text=True,capture_output=True,timeout=160)
    self.assertEqual(result.returncode,0,result.stderr[-9000:])
    return result.stdout.strip(),result.stderr
   self.assertTrue(sql("SHOW server_version_num;")[0].startswith(version))
   sql(FIXTURE)
   src=MIGRATION.read_text(encoding="utf-8")
   self.assertIn("SKILL_SELECTION_LATE",src)
   self.assertNotIn("UPDATE public.lf_operation_execution_steps",src)
   for signature,expected in EXPECTED:
    self.assertEqual(src.count("'"+expected+"'"),1,(signature,expected))
    actual=sql("SELECT md5(pg_get_functiondef('"+signature+"'::regprocedure));")[0]
    self.assertRegex(actual,r"^[0-9a-f]{32}$")
    # In the disposable fixture ONLY, use its hash to prove the patch is
    # source pinned while testing executable PL/pgSQL on PostgreSQL 17/18.
    src=src.replace(expected,actual,1)
   body=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;\n",1)[0]
   stdout,stderr=sql("BEGIN;\n"+body+"\n"+CHECKS+"\nROLLBACK;\n"+
     "SELECT CASE WHEN to_regclass('public.lf_profile_skill_late_receipt_v1') IS NULL "+
     "THEN 'PASS_ROLLBACK' ELSE 'FAIL_ROLLBACK' END;")
   self.assertEqual(stdout.splitlines()[-1],"PASS_ROLLBACK")
   for marker in [
    "PASS_STEP40_NO_SKILL_AND_SELECTOR_CONTENT_FINDING",
    "PASS_STEP40_SELECTED_SKILL_CANONICAL_RECEIPT",
    "PASS_FAILED_SKILL_IS_FINDING_STEP40_PASS",
    "PASS_LATE_SKILL_INVOKED_ONCE_READBACK_AND_HISTORICAL_PASS_IMMUTABLE",
   ]:
    self.assertIn(marker,stderr,stderr)
   print("PASS_LF_SKILL_LATE_SELECTION_PG"+version+"_ROLLBACK",flush=True)
  finally:
   subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=60)
 def test_pg17(self):self.check("postgres:17.6","170006")
 def test_pg18(self):self.check("postgres:18.7","180007")

if __name__=="__main__": unittest.main()
