"""IG0815: current-function PG17/18 integration, BEGIN/ROLLBACK only.
Tests synthetic fixtures, NEVER a real LF RUN or promotion on Supabase.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
MIGRATION = BASE / "supabase/migrations/20261116133000_lf_auto_score_authority_without_profile_v1.sql"
SOURCE = Path(__file__).parent / "fixtures/lf_ig0815_promotion_live_source_20261116.sql"
SCHEMA = r"""
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY, operation_code text, target_code text, status text
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text, step_order integer, step_id text, status text,
 evidence_payload jsonb DEFAULT '{}'::jsonb, observed_at timestamptz DEFAULT now(),
 PRIMARY KEY(execution_id,step_order)
);
CREATE TABLE public.lf_profile_write_authority_v1 (
 profile_code text, operation_code text, status text
);
CREATE TABLE lf_ops.reglas (
 codigo text PRIMARY KEY, estado text NOT NULL, categoria text NOT NULL,
 pendiente_decision boolean NOT NULL, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE lf_ops.regla_behavior_tests (
 regla_codigo text, test_ref text, ci_run text, pg17 text, pg18 text
);
CREATE SEQUENCE public.lf_promotion_id_seq;
CREATE TABLE public.lf_rule_promotion_v1 (
 promotion_id text PRIMARY KEY DEFAULT ('PROM-'||nextval('public.lf_promotion_id_seq')::text),
 rule_code text, request_execution_id text, requested_by_profile text,
 request_snapshot_sha256 text, reason text, status text DEFAULT 'PENDING',
 decided_by text, decided_at timestamptz, applied_at timestamptz
);
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(p_type text,p_rule_code text)
 RETURNS text LANGUAGE sql STABLE AS $f$
 SELECT md5(r.codigo||'|'||r.estado||'|'||r.categoria||'|'||
            r.pendiente_decision::text||'|'||r.updated_at::text)
 FROM lf_ops.reglas r WHERE p_type='REGLA' AND r.codigo=p_rule_code
 $f$;
"""
TEST = r"""
BEGIN;
DO $check$ BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))
   = '61ab4c8363f09309385ff80a82697717'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
   = 'e36f54b29ad49e2b87b1a670e31cde30'
 THEN RAISE EXCEPTION 'IG0815_PREIMAGE_STILL_INSTALLED'; END IF;
 IF position('PERFIL-PRODUCT-DIRECTOR-LF' IN
   pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))>0
 THEN RAISE EXCEPTION 'IG0815_FIXED_PRODUCT_DIRECTOR_REMAINING'; END IF;
END $check$;
CREATE FUNCTION pg_temp.seed_run(p_run text,p_profile text,p_bound_rule text,p_complete boolean DEFAULT true)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 INSERT INTO public.lf_operation_execution VALUES
   (p_run,'EJECUCION_PERFIL_LF',p_profile,'COMPLETED');
 INSERT INTO public.lf_operation_execution_steps
     (execution_id,step_order,step_id,status,evidence_payload,observed_at)
 SELECT p_run,n,
 CASE n WHEN 0 THEN 'init_execution' WHEN 10 THEN 'router'
 WHEN 20 THEN 'profile_resolve' WHEN 30 THEN 'profile_source_read'
 WHEN 40 THEN 'input_validate' WHEN 45 THEN 'context_admission'
 WHEN 47 THEN 'research_baseline_freeze' WHEN 50 THEN 'execute_profile'
 WHEN 60 THEN 'output_validate' WHEN 70 THEN 'semantic_judge'
 ELSE 'report_output' END,
 'STEP_PASS_WITH_EVIDENCE',
 CASE n WHEN 40 THEN
  jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('b',64))
 WHEN 50 THEN
  jsonb_build_object('raw_output_sha256',repeat('a',64),'profile_output',
    jsonb_build_object('deliverable_created',
      jsonb_build_object('product_decision',
        jsonb_build_object('source_refs',CASE WHEN p_bound_rule IS NULL THEN '[]'::jsonb
        ELSE jsonb_build_array(jsonb_build_object('source_ref',
             'supabase://lf_ops.reglas/'||p_bound_rule)) END))))
 WHEN 60 THEN jsonb_build_object('raw_output_sha256',repeat('a',64))
 WHEN 70 THEN jsonb_build_object('semantic_judge_result',
  jsonb_build_object('verdict','PASS_REVIEWED_CURRENT_CONTEXT',
   'candidate_sha256',repeat('a',64),'scope_packet_sha256',repeat('b',64),
   'judge_v3_evidence',jsonb_build_object('unsupported_claims','[]'::jsonb)))
 ELSE '{}'::jsonb END,
 now()
 FROM unnest(ARRAY[0,10,20,30,40,45,47,50,60,70,80]) AS n
 WHERE p_complete OR n<>47;
END $f$;

INSERT INTO public.lf_profile_write_authority_v1
 VALUES ('PERFIL-MANUAL-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision,updated_at)
 SELECT code,'CANDIDATO',CASE WHEN code='B2B-RULE-AUTH-001' THEN 'AUTH' ELSE 'UX' END,
 FALSE,now()-interval '2 hours'
 FROM unnest(ARRAY[
 'SAFE-AUTO','SAFE-LOW','SAFE-LOW-NOAUTH','B2B-RULE-AUTH-001',
 'SAFE-ACTOR','SAFE-STALE','SAFE-WRONG','SAFE-MISSING','SAFE-BROKEN',
 'SAFE-HASH']) AS code;
INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18)
 SELECT codigo,'fixtures://IG0815_SOURCE_BOUND','CI_FIXTURE_ONLY','PASS','PASS'
 FROM lf_ops.reglas WHERE codigo<>'SAFE-LOW' AND codigo<>'SAFE-LOW-NOAUTH';
SELECT pg_temp.seed_run('RUN-AUTO','PERFIL-REPARADOR-LF','SAFE-AUTO');
SELECT pg_temp.seed_run('RUN-LOW','PERFIL-MANUAL-LF','SAFE-LOW');
SELECT pg_temp.seed_run('RUN-LOW-NOAUTH','PERFIL-REPARADOR-LF','SAFE-LOW-NOAUTH');
SELECT pg_temp.seed_run('RUN-AUTH','PERFIL-MANUAL-LF','B2B-RULE-AUTH-001');
SELECT pg_temp.seed_run('RUN-ACTOR','PERFIL-REPARADOR-LF','SAFE-ACTOR');
SELECT pg_temp.seed_run('RUN-STALE','PERFIL-REPARADOR-LF','SAFE-STALE');
SELECT pg_temp.seed_run('RUN-OTHER','PERFIL-REPARADOR-LF','SAFE-AUTO');
SELECT pg_temp.seed_run('RUN-MISSING','PERFIL-REPARADOR-LF',NULL);
SELECT pg_temp.seed_run('RUN-BROKEN','PERFIL-REPARADOR-LF','SAFE-BROKEN',false);
SELECT pg_temp.seed_run('RUN-HASH','PERFIL-REPARADOR-LF','SAFE-HASH');
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{raw_output_sha256}',
    to_jsonb(repeat('c',64)))
 WHERE execution_id='RUN-HASH' AND step_order=60;

DO $assert$ DECLARE v jsonb; p text; snap text;
BEGIN
 -- 1. AUTO/100, no profile authority, different from fixed Product Director -> APPLIED.
 IF EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
           WHERE profile_code='PERFIL-REPARADOR-LF') THEN
   RAISE EXCEPTION 'IG0815_FIXTURE_REPAIR_ALREADY_AUTHORIZED'; END IF;
 v:=public.lf_rule_promotion_score_v1('RUN-AUTO','SAFE-AUTO');
 IF v->>'score'<>'100' OR v->>'decision'<>'AUTO'
   OR v->>'hard_block'<>'false' OR v->>'next_gate'<>'PROMOTION_REQUEST'
 THEN RAISE EXCEPTION 'IG0815_AUTO_PRECONDITION:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-AUTO','SAFE-AUTO','IG0815 transaction-only positive');
 IF v->>'status'<>'APPLIED' OR (SELECT estado FROM lf_ops.reglas WHERE codigo='SAFE-AUTO')<>'VIGENTE'
 OR NOT EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
    WHERE rule_code='SAFE-AUTO' AND status='APPLIED' AND decided_by='AUTO_SCORE_V1'
      AND requested_by_profile='PERFIL-REPARADOR-LF')
 THEN RAISE EXCEPTION 'IG0815_AUTO_REPAIR_NOT_APPLIED:%',v; END IF;
 RAISE NOTICE 'PASS_1_AUTO_REPAIR_SCORE100_APPLIED';

 -- 2. Score under 85 cannot use AUTO; HUMAN still works under unchanged grant.
 v:=public.lf_rule_promotion_score_v1('RUN-LOW','SAFE-LOW');
 IF v->>'score'<>'60' OR v->>'decision'<>'MANUAL'
 THEN RAISE EXCEPTION 'IG0815_LOW_SCORE_BAD:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-LOW','SAFE-LOW','IG0815 manual fixture');
 IF v->>'status'<>'PENDING_HUMAN_APPROVAL'
 THEN RAISE EXCEPTION 'IG0815_MANUAL_REQUEST_BLOCKED:%',v; END IF;
 p:=v->>'promotion_id';
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','AUTO_SCORE_V1','must block');
 IF v->>'blocking_code'<>'AUTO_SCORE_AUTHORITY_NOT_ATTESTED'
 THEN RAISE EXCEPTION 'IG0815_SCORE_LOW_AUTO_ACCEPTED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','HUMAN:ig0815-fixture','manual valid');
 IF v->>'status'<>'APPROVED'
 THEN RAISE EXCEPTION 'IG0815_HUMAN_PATH_REGRESSED:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-LOW-NOAUTH','SAFE-LOW-NOAUTH','should refuse unauthorised manual');
 IF v->>'blocking_code'<>'PROFILE_NOT_AUTHORIZED_FOR_PROMOTION'
 THEN RAISE EXCEPTION 'IG0815_MANUAL_ROLE_BYPASSED:%',v; END IF;
 RAISE NOTICE 'PASS_2_LOW_SCORE_AUTO_BLOCKED_HUMAN_INTACT';

 -- 3. AUTH hard-block even at score 100. HUMAN: is required, never AUTO.
 v:=public.lf_rule_promotion_score_v1('RUN-AUTH','B2B-RULE-AUTH-001');
 IF v->>'score'<>'100' OR v->>'hard_block'<>'true' OR v->>'decision'<>'MANUAL'
 THEN RAISE EXCEPTION 'IG0815_AUTH_SCORER_BYPASSED:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-AUTH','B2B-RULE-AUTH-001','manual auth');
 IF v->>'status'<>'PENDING_HUMAN_APPROVAL'
 THEN RAISE EXCEPTION 'IG0815_AUTH_NO_MANUAL:%',v; END IF;
 p:=v->>'promotion_id';
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','AUTO_SCORE_V1','must refuse AUTH');
 IF v->>'blocking_code'<>'AUTO_SCORE_AUTHORITY_NOT_ATTESTED'
 THEN RAISE EXCEPTION 'IG0815_AUTH_AUTO_BYPASSED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','HUMAN:ig0815-fixture','manual auth');
 IF v->>'status'<>'APPROVED'
 THEN RAISE EXCEPTION 'IG0815_AUTH_HUMAN_REGRESSED:%',v; END IF;
 RAISE NOTICE 'PASS_3_AUTH_HARD_BLOCK_MANUAL';

 -- 4. Invalid actors and AUTO REJECT fail closed.
 INSERT INTO public.lf_rule_promotion_v1(rule_code,request_execution_id,
 requested_by_profile,request_snapshot_sha256,reason) VALUES
 ('SAFE-ACTOR','RUN-ACTOR','PERFIL-REPARADOR-LF',
  public.lf_asset_snapshot_sha_v1('REGLA','SAFE-ACTOR'),'actor negative')
 RETURNING promotion_id INTO p;
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','BOT:service','must block');
 IF v->>'blocking_code'<>'APPROVER_MUST_BE_HUMAN'
 THEN RAISE EXCEPTION 'IG0815_INVALID_ACTOR_ACCEPTED:%',v; END IF;
 v:=public.lf_rule_promotion_decide_v1(p,'REJECT','AUTO_SCORE_V1','must block');
 IF v->>'blocking_code'<>'AUTO_SCORE_ONLY_APPROVE'
 THEN RAISE EXCEPTION 'IG0815_AUTO_REJECT_ACCEPTED:%',v; END IF;
 RAISE NOTICE 'PASS_4_INVALID_ACTOR_REJECTED';

 -- 5. Snapshot drift returns STALE before approval.
 INSERT INTO public.lf_rule_promotion_v1(rule_code,request_execution_id,
 requested_by_profile,request_snapshot_sha256,reason) VALUES
 ('SAFE-STALE','RUN-STALE','PERFIL-REPARADOR-LF',
  public.lf_asset_snapshot_sha_v1('REGLA','SAFE-STALE'),'stale negative')
 RETURNING promotion_id INTO p;
 UPDATE lf_ops.reglas SET categoria='VISUAL' WHERE codigo='SAFE-STALE';
 v:=public.lf_rule_promotion_decide_v1(p,'APPROVE','AUTO_SCORE_V1','must be stale');
 IF v->>'blocking_code'<>'PROMOTION_STALE'
 OR (SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id=p)<>'STALE'
 THEN RAISE EXCEPTION 'IG0815_STALE_APPROVED:%',v; END IF;
 RAISE NOTICE 'PASS_5_SNAPSHOT_STALE_REJECTED';

 -- 6. RAW references belonging to a different rule or absent must fail.
 -- Give repair profile a temporary fixture-only MANUAL grant to reach the RAW guard;
 -- AUTO without that grant was independently proven in case 1.
 INSERT INTO public.lf_profile_write_authority_v1
   VALUES ('PERFIL-REPARADOR-LF','PROMOCION_REGLA_LF','ACTIVE');
 v:=public.lf_rule_promotion_request_v1('RUN-OTHER','SAFE-WRONG','wrong RAW ref');
 IF v->>'blocking_code'<>'PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED'
 THEN RAISE EXCEPTION 'IG0815_WRONG_RULE_RAW_ACCEPTED:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-MISSING','SAFE-MISSING','missing RAW ref');
 IF v->>'blocking_code'<>'PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED'
 THEN RAISE EXCEPTION 'IG0815_MISSING_RULE_RAW_ACCEPTED:%',v; END IF;
 v:=public.lf_rule_promotion_request_v1('RUN-HASH','SAFE-HASH','broken 60 hash');
 IF v->>'blocking_code'<>'PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED'
 THEN RAISE EXCEPTION 'IG0815_BROKEN_HASH_ACCEPTED:%',v; END IF;
 RAISE NOTICE 'PASS_6_WRONG_MISSING_RAW_AND_BROKEN_HASH_REJECTED';

 -- Additional: no AUTO when the parent is not 11/11.
 v:=public.lf_rule_promotion_request_v1('RUN-BROKEN','SAFE-BROKEN','only 10 steps');
 IF v->>'blocking_code'<>'COMPLETED_PARENT_STEPS_NOT_CLEAN'
 THEN RAISE EXCEPTION 'IG0815_INCOMPLETE_PARENT_ACCEPTED:%',v; END IF;
 RAISE NOTICE 'PASS_7_11_STEP_PARENT_GUARD';
END $assert$;
SELECT 'IG0815_IN_TX_APPLIED='||count(*) FROM public.lf_rule_promotion_v1 WHERE status='APPLIED';
ROLLBACK;
SELECT 'IG0815_NO_PROMOTION_RESIDUE='||count(*) FROM public.lf_rule_promotion_v1;
SELECT 'IG0815_NO_RULE_RESIDUE='||count(*) FROM lf_ops.reglas;
SELECT 'IG0815_NO_RUN_RESIDUE='||count(*) FROM public.lf_operation_execution;
"""
class IG0815DualPG(unittest.TestCase):
 def test_current_source_auto_without_profile_and_manual_unchanged(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=MIGRATION.read_text(encoding="utf-8")
  source=SOURCE.read_text(encoding="utf-8")
  for version in ("17.6","18.7"):
   with self.subTest(postgres=version):
    name="lf-ig0815-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
                        "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                       capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr)
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(contents):
      q=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t","-v","ON_ERROR_STOP=1",
       "-U","postgres","-d","postgres"],input=contents,capture_output=True,text=True,timeout=180)
      self.assertEqual(q.returncode,0,q.stderr[-4500:]+"\n"+q.stdout[-2500:])
      return q.stdout+"\n"+q.stderr
     sql(SCHEMA+"\n"+source)
     sql(migration)
     output=sql(TEST)
     for receipt in ["PASS_1_AUTO_REPAIR_SCORE100_APPLIED",
                     "PASS_2_LOW_SCORE_AUTO_BLOCKED_HUMAN_INTACT",
                     "PASS_3_AUTH_HARD_BLOCK_MANUAL",
                     "PASS_4_INVALID_ACTOR_REJECTED",
                     "PASS_5_SNAPSHOT_STALE_REJECTED",
                     "PASS_6_WRONG_MISSING_RAW_AND_BROKEN_HASH_REJECTED",
                     "PASS_7_11_STEP_PARENT_GUARD",
                     "IG0815_NO_PROMOTION_RESIDUE=0",
                     "IG0815_NO_RULE_RESIDUE=0",
                     "IG0815_NO_RUN_RESIDUE=0"]:
      self.assertIn(receipt,output,output[-3500:])
     print("IG0815_PG"+version+"_BEGIN_ROLLBACK_7_CASES_PASS",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":
 unittest.main()
