"""LF independent judge on existing Step70 + owner-batch promotion, PG17.6/18.7.

Synthetic review proofs exercise a *guard*; these are not real independent
model calls or authenticated-human receipts. Production remains NO-GO.
"""
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261114163200_lf_rule_promotion_independent_step70_existing_route_v1.sql"
SOURCE=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_rule_promotion_legacy_route_source_20261114.sql"
PREIMAGE="2fcac9f18b1581985af93639e475cd1a"

SCHEMA=r"""
CREATE ROLE service_role;
CREATE SCHEMA programacion;
CREATE FUNCTION programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)
 RETURNS TABLE(regla_id bigint,regla_codigo text,screens integer,criteria jsonb,
 verdict text,failed text[]) LANGUAGE sql STABLE AS $
 SELECT NULL::bigint,NULL::text,0,'{}'::jsonb,'HOLD'::text,ARRAY[]::text[]
 WHERE false $;
CREATE SCHEMA lf_ops;
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text,target_code text,status text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_order integer,step_id text,status text,evidence_payload jsonb,
 PRIMARY KEY(execution_id,step_order));
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY,estado text NOT NULL);
CREATE TABLE public.lf_rule_promotion_v1(
 promotion_id text PRIMARY KEY DEFAULT ('PROMO-'||substr(md5(random()::text),1,16)),
 rule_code text NOT NULL,request_execution_id text,requested_by_profile text,
 request_snapshot_sha256 text,status text NOT NULL DEFAULT 'PENDING',
 reason text,decided_by text,decided_at timestamptz,applied_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now());
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(text,text)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT repeat('a',64) $$;
INSERT INTO public.lf_operation_execution VALUES
 ('PARENT-1','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS');
INSERT INTO public.lf_profile_write_authority_v1 VALUES
 ('PERFIL-PRODUCT-DIRECTOR-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO lf_ops.reglas VALUES('RULE-CAND-001','CANDIDATO');
INSERT INTO public.lf_operation_execution_steps VALUES
 ('PARENT-1',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
  '{"scope_authority_packet_sha256":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'),
 ('PARENT-1',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
  '{"raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "profile_output":{"deliverable_created":{"product_decision":{"source_refs":[
      {"source_ref":"supabase://lf_ops.reglas/RULE-CAND-001"}]}}}}'),
 ('PARENT-1',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
  '{"output_contract_result":"PASS",
    "raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'),
 ('PARENT-1',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
  '{"semantic_judge_result":{"verdict":"PASS_REVIEWED_CURRENT_CONTEXT",
  "review_mode":"CURRENT_CONTEXT_REVIEW","model_call_count":0,
  "reviewer_is_producer":true,"producer_independence_proven":false,
  "candidate_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "scope_packet_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "unsupported_claims":[]}}');
"""


class PGIndependentPromotionTest(unittest.TestCase):
    def test_existing_route_requires_real_independent_step70_and_rollback(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        sql=MIG.read_text(encoding="utf-8")
        self.assertEqual(sql.count(PREIMAGE),1)
        self.assertIn("PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED",sql)
        self.assertNotIn("CREATE TABLE public.lf_operation_execution_steps",sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1",sql)
        # Do not execute the migration COMMIT in test; run in BEGIN..ROLLBACK.
        body=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;\n",1)[0]
        source=SOURCE.read_text(encoding="utf-8")
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-promote-"+uuid.uuid4().hex[:11]
                p=subprocess.run(["docker","run","-d","--rm","--name",name,
                      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                      capture_output=True,text=True,timeout=180)
                self.assertEqual(p.returncode,0,p.stderr)
                try:
                    for _ in range(80):
                        ready=subprocess.run(["docker","exec",name,"pg_isready",
                           "-U","postgres"],capture_output=True,timeout=8)
                        if ready.returncode==0: break
                        time.sleep(.7)
                    self.assertEqual(ready.returncode,0)
                    def psql(text,good=True):
                        r=subprocess.run(["docker","exec","-i",name,"psql",
                             "-X","-A","-t","-U","postgres","-d","postgres",
                             "-v","ON_ERROR_STOP=1"],
                             input=text,capture_output=True,text=True,timeout=120)
                        if good: self.assertEqual(r.returncode,0,r.stderr[-4000:])
                        else: self.assertNotEqual(r.returncode,0,r.stdout)
                        return r
                    psql(SCHEMA+"\n"+source+"\nCREATE TRIGGER "
                      "lf_rule_promotion_guard BEFORE UPDATE ON lf_ops.reglas "
                      "FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();")
                    livehash=psql("SELECT md5(pg_get_functiondef("
                       "'public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure));"
                       ).stdout.strip()
                    self.assertRegex(livehash,"^[0-9a-f]{32}$")
                    lab=body.replace(PREIMAGE,livehash)
                    self.assertIn("LF_PROMOTION_REQUEST_SOURCE_STATE_DRIFT",lab)

                    same=psql("BEGIN;\n"+lab+"\n"
                       "SELECT public.lf_rule_promotion_request_v1("
                       "'PARENT-1','RULE-CAND-001','evidence') AS check_same;\n"
                       "ROLLBACK;")
                    self.assertIn("PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED",same.stdout)
                    # A synthetic independent profile reviewer proof only tests
                    # the guard, not actual model independence or owner identity.
                    mark=r"""
UPDATE public.lf_operation_execution_steps
 SET evidence_payload='{"semantic_judge_result":{
  "verdict":"PASS_INDEPENDENT_SEMANTIC",
  "model_call_count":1,"producer_independence_proven":true,
  "judge_v3_evidence":{"judge_invocation_kind":"NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE",
    "judge_role":"INDEPENDENT_REVIEWER_NOT_PRODUCT_DIRECTOR_PRODUCER",
    "unsupported_claims":[]},
  "candidate_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "scope_packet_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "unsupported_claims":[]}}'::jsonb
 WHERE execution_id='PARENT-1' AND step_order=70;
"""
                    submit=r"""
SELECT 'REQUEST='||(public.lf_rule_promotion_request_v1(
'PARENT-1','RULE-CAND-001','independently reviewed profile evidence')->>'status');
SELECT 'PENDING='||count(*) FROM public.lf_rule_promotion_v1 WHERE status='PENDING';
SELECT 'NONHUMAN='||(public.lf_rule_promotion_decide_batch_v1(
array(SELECT promotion_id FROM public.lf_rule_promotion_v1),
'APPROVE','BOT:SIMULATED','no') ->>'blocked');
SELECT 'APPROVAL='||(public.lf_rule_promotion_decide_batch_v1(
array(SELECT promotion_id FROM public.lf_rule_promotion_v1),
'APPROVE','HUMAN:OWNER_FIXTURE','synthetic only') ->>'ok');
SELECT 'BEFORE_APPLY='||estado FROM lf_ops.reglas WHERE codigo='RULE-CAND-001';
SELECT 'APPLY='||(public.lf_rule_promotion_apply_batch_v1(
array(SELECT promotion_id FROM public.lf_rule_promotion_v1)) ->>'applied');
SELECT 'AFTER_APPLY='||estado FROM lf_ops.reglas WHERE codigo='RULE-CAND-001';
"""
                    ok=psql("BEGIN;\n"+lab+"\n"+mark+"\n"+submit+
                      "\nROLLBACK;\n"
                      "SELECT 'POST_ROLLBACK='||estado FROM lf_ops.reglas;\n"
                      "SELECT 'PROMO_ROWS='||count(*) FROM public.lf_rule_promotion_v1;")
                    for check in ("REQUEST=PENDING_HUMAN_APPROVAL",
                           "PENDING=1","NONHUMAN=1","APPROVAL=1",
                           "BEFORE_APPLY=CANDIDATO","APPLY=1",
                           "AFTER_APPLY=VIGENTE","POST_ROLLBACK=CANDIDATO",
                           "PROMO_ROWS=0"):
                        self.assertIn(check,ok.stdout,check+"\n"+ok.stdout)

                    altered=psql("BEGIN;\nCREATE OR REPLACE FUNCTION "
                         "public.lf_rule_promotion_request_v1(text,text,text) "
                         "RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;\n"
                         +lab+"\nROLLBACK;",good=False)
                    self.assertIn("LF_PROMOTION_REQUEST_SOURCE_STATE_DRIFT",altered.stderr)
                    print("PASS_PROMOTION_STEP70_PG"+pg+
                       "_same_model_blocks_owner_batch_synthetic_rollback")
                finally:
                    subprocess.run(["docker","rm","-f",name],
                          capture_output=True,timeout=30)
