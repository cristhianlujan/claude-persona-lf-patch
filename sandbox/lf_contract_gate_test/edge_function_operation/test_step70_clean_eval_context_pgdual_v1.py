"""PG17/18 transactional regression for ACT-0001 Step70 clean-eval context mode.

All receipts here are *synthetic fixtures*; NO independent LLM is invoked,
and no production/real RUN PASS is claimed. Every database change rolls back.
"""
import hashlib
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261115040500_lf_step70_clean_eval_context_same_llm_v1.sql"
PRE=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_step70_clean_eval_preimage_20261115.sql"
RUN="EXEC-PROFILE-GATE2-TESTCLEANSCTX00123456"
CAND="a"*64
SCOPE="b"*64
LIVE_MD5="6e42b9cd2738b8c25049f7235b2fa188"
ART=f"actions://fixture/{RUN}/profile-native-output.json"

def sha(x):
    return hashlib.sha256(x.encode("utf8")).hexdigest()

def quote(x):
    return "'"+x.replace("'","''")+"'"

def compact(x):
    return json.dumps(x,sort_keys=True,separators=(",",":"),ensure_ascii=False)

def context_events():
    bundle=sha("LF_STEP70_FROZEN_BUNDLE_V1|"+CAND+"|"+SCOPE+"|"+ART)
    base={"execution_id":RUN,"candidate_sha256":CAND,"scope_packet_sha256":SCOPE,
          "frozen_bundle_sha256":bundle,"nonce":"test-only-disposable-nonce-a"}
    reviewer={"review_mode":"INDEPENDENT_EVAL_CONTEXT","reviewer_context_ref":"context://test/reviewer-2",
              "reviewer_is_producer":False,"producer_independence_proven":True}
    rows=[
        {**base,"stage":"REQUEST"},
        {**base,"stage":"EXECUTOR","executor_context_ref":"context://test/producer-1",
         "producer_schema_id":"SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6",
         "producer_eval_id":"PROFILE_OUTPUT_VALIDATION_RESULT_V1",
         "producer_profile_id":"PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"},
        {**base,"stage":"JUDGE","review_mode":"INDEPENDENT_EVAL_CONTEXT",
         "reviewer_context_ref":"context://test/reviewer-2",
         "reviewer_schema_id":"LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1",
         "reviewer_eval_id":"LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1",
         "reviewer_profile_id":"PERFIL-QUALITY-PACK","reviewer_context_cleared":True,
         "eval_status":"PASS","review_payload":reviewer},
    ]
    return rows,{"review_mode":"INDEPENDENT_EVAL_CONTEXT",
                 "candidate_sha256":CAND,"scope_packet_sha256":SCOPE,
                 "judge_v3_evidence":reviewer}

class CleanContextPgDual(unittest.TestCase):
    def test_pg17(self): self.exercise("postgres:17.6")
    def test_pg18(self): self.exercise("postgres:18.7")

    def exercise(self,image):
        if not shutil.which("docker"):
            self.fail("DOCKER_REQUIRED_FOR_PG17_PG18_ROLLBACK_TEST")
        name="lf-step70-clean-"+uuid.uuid4().hex[:12]
        start=subprocess.run(["docker","run","-d","--rm","--name",name,"-e",
                              "POSTGRES_PASSWORD=postgres",image],
                             capture_output=True,text=True,timeout=150)
        self.assertEqual(start.returncode,0,start.stderr[-1600:])
        try:
            for _ in range(75):
                r=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                    capture_output=True,text=True,timeout=8)
                if r.returncode==0:break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            self._exercise_connected(name)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

    def sql(self,name,statement,success=True):
        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
                          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                         input=statement,text=True,capture_output=True,timeout=110)
        if success: self.assertEqual(p.returncode,0,p.stderr[-2600:])
        else: self.assertNotEqual(p.returncode,0,"EXPECTED_NEGATIVE_PG_REJECT")
        return p.stdout,p.stderr

    def _exercise_connected(self,name):
        sql="""CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE ROLE anon NOLOGIN;CREATE ROLE authenticated NOLOGIN;CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
 status text,manifest jsonb NOT NULL DEFAULT '{}'::jsonb,created_at timestamptz DEFAULT now());
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text,step_id text,step_order integer,status text,evidence_ref text,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,created_at timestamptz DEFAULT now(),
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_ig_native_chat_receipt_v1 (
 execution_id text,seq integer,kind text,raw_text text,raw_sha256 text,prev_sha256 text,
 chain_sha256 text,writer_receipt_ref text,writer_receipt_sha256 text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(execution_id,seq));
"""
        sql+=PRE.read_text(encoding="utf8")+"\n"
        sql+=f"""INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest)
VALUES({quote(RUN)},'EJECUCION_PERFIL_LF','PERFIL','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
'{{"executor_mode":"GPT_NATIVE","executor_provider":"OPENAI_CHATGPT_NATIVE",
"no_promotion":true,"governed_repair_write":true}}'::jsonb);
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,step_order,status,evidence_ref,evidence_payload)
VALUES
({quote(RUN)},'input_validate',40,'STEP_PASS_WITH_EVIDENCE','supabase://fixture/step40',
'{{"scope_authority_packet_sha256":"sha256:{SCOPE}"}}'::jsonb),
({quote(RUN)},'execute_profile',50,'STEP_PASS_WITH_EVIDENCE',{quote(ART)},
'{{"raw_output_sha256":"{CAND}"}}'::jsonb),
({quote(RUN)},'output_validate',60,'STEP_PASS_WITH_EVIDENCE','supabase://fixture/step60',
'{{"deterministic_validation":{{"status":"PASS"}}}}'::jsonb);
"""
        self.sql(name,sql)
        actual,_=self.sql(name,"SELECT md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));")
        actual=actual.strip()
        self.assertRegex(actual,r"^[0-9a-f]{32}$")
        source=MIG.read_text(encoding="utf8")
        self.assertIn("LF_STEP70_CLEAN_EVAL_BRIDGE_PREIMAGE_DRIFT",source)
        self.assertIn(LIVE_MD5,source)
        # Adjust only the disposable PG17/18 fixture's server-specific
        # pg_get_functiondef pretty printer digest, not source migration.
        body=source.replace(LIVE_MD5,actual)
        body=re.sub(r"^BEGIN;\s*","",body,count=1)
        body=re.sub(r"\s*COMMIT;\s*$","",body)
        self.assertIn("CREATE FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1",body)
        # CAS must reject a modified deployed function.
        self.sql(name,"BEGIN;"+body.replace(actual,"0"*32,1)+";ROLLBACK;",success=False)
        probe,_=self.sql(name,"SELECT to_regprocedure('public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)') IS NULL;")
        self.assertEqual(probe.strip(),"t")
        # Functional check is confined to one transaction and ROLLBACK.
        events,review=context_events()
        chain="0"*64
        ins=""
        for i,event in enumerate(events,1):
            raw=compact(event)
            raw_sha=sha(raw)
            writer_sha="f"*64
            next_hash=sha(f"LF_NATIVE_CHAT_EVENT_V1|{RUN}|{i}|{event['stage']}|{raw_sha}|{chain}|{writer_sha}")
            ins+=f"""INSERT INTO public.lf_ig_native_chat_receipt_v1
(execution_id,seq,kind,raw_text,raw_sha256,prev_sha256,chain_sha256,writer_receipt_ref,writer_receipt_sha256)
VALUES({quote(RUN)},{i},{quote(event['stage'])},{quote(raw)},{quote(raw_sha)},
{quote(chain)},{quote(next_hash)},'actions://fixture/clean-context-receipt',{quote(writer_sha)});\n"""
            chain=next_hash
        v=quote(compact(review))
        statement=f"""BEGIN;
{body}
SELECT 'MISSING|'||(public.lf_profile_step70_clean_eval_context_verify_v1({quote(RUN)},{v}::jsonb)->>'blocking_code');
{ins}
SELECT 'VALID|'||(public.lf_profile_step70_clean_eval_context_verify_v1({quote(RUN)},{v}::jsonb)->>'status');
SELECT 'DRIFT|'||(public.lf_profile_step70_clean_eval_context_verify_v1({quote(RUN)},
jsonb_set({v}::jsonb,'{{candidate_sha256}}','"{'c'*64}"'::jsonb))->>'blocking_code');
ROLLBACK;"""
        out,_=self.sql(name,statement)
        self.assertIn("MISSING|LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED",out)
        self.assertIn("VALID|CLEAN_CONTEXT_EVAL_VERIFIED",out)
        self.assertIn("DRIFT|LF_STEP70_CLEAN_CONTEXT_SOURCE_SHA_DRIFT",out)
        after,_=self.sql(name,"SELECT to_regprocedure('public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)') IS NULL;")
        self.assertEqual(after.strip(),"t","PG_ROLLBACK_LEAK")
        post,_=self.sql(name,"SELECT count(*) FROM public.lf_ig_native_chat_receipt_v1;")
        self.assertEqual(post.strip(),"0","PG_ROLLBACK_DATA_LEAK")

if __name__=="__main__":
    unittest.main()
