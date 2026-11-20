"""LF native-chat receipt writer / PG17.6 and PG18.7, BEGIN/ROLLBACK.

All model/eval/context values are SYNTHETIC test fixtures. No production or
real review is performed. Only the existing Step70 verifier is reused.
"""
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261115053500_lf_ig_native_chat_receipt_append_governed_v1.sql"
STEP70 = ROOT / "supabase/migrations/20261115040500_lf_step70_clean_eval_context_same_llm_v1.sql"
RUN = "EXEC-PROFILE-GATE2-PGWRITERCONTEXTTEST001"
SCOPE = "b"*64
PROFILE = "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"
SCHEMA = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
EVAL = "PROFILE_OUTPUT_VALIDATION_RESULT_V1"
REF = "actions://fixture/step50/raw.json"

def q(value):
    return "'" + str(value).replace("'", "''") + "'"

def clean_ddl(source):
    text = source.strip()
    text = re.sub(r"^BEGIN;\s*", "", text, count=1)
    text = re.sub(r"\s*COMMIT;\s*$", "", text, count=1)
    return text

def writer(kind, event, ref=None):
    if ref is None:
        ref = "actions://fixture/worker/" + kind
    return ("public.lf_ig_native_chat_receipt_append_v1("
            +q(RUN)+","+q(kind)+","+event+"::jsonb,"+q(ref)+")")

EXEC = q(
    '{"executor_context_ref":"context://fixture/producer-real",'
    '"producer_schema_id":"'+SCHEMA+'",'
    '"producer_eval_id":"'+EVAL+'",'
    '"producer_profile_id":"'+PROFILE+'"}'
)
REVIEWER_CONTEXT = "context://fixture/reviewer-independent"
def judge(context=REVIEWER_CONTEXT):
    raw_review = (
       "jsonb_build_object('review_mode','INDEPENDENT_EVAL_CONTEXT',"
       "'candidate_sha256',"
       "(SELECT evidence_payload->>'raw_output_sha256' "
       " FROM public.lf_operation_execution_steps "
       " WHERE execution_id="+q(RUN)+" AND step_id='execute_profile'),"
       "'scope_packet_sha256',"+q(SCOPE)+","
       "'reviewer_context_ref',"+q(context)+","
       "'verdict','PASS_INDEPENDENT_SEMANTIC')"
    )
    return ("jsonb_build_object("
        "'review_mode','INDEPENDENT_EVAL_CONTEXT',"
        "'reviewer_context_ref',"+q(context)+","
        "'reviewer_schema_id','LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1',"
        "'reviewer_eval_id','LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1',"
        "'reviewer_profile_id','PERFIL-QUALITY-PACK',"
        "'reviewer_context_cleared',true,"
        "'eval_status','PASS',"
        "'review_payload',"+raw_review+")"
    )

class PgWriterRollback(unittest.TestCase):
    def test_pg17(self): self.exercise("postgres:17.6")
    def test_pg18(self): self.exercise("postgres:18.7")

    def run_sql(self, name, statement, success=True, timeout=130):
        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
            "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
            input=statement,capture_output=True,text=True,timeout=timeout)
        if success:
            self.assertEqual(p.returncode, 0, p.stderr[-3500:])
        else:
            self.assertNotEqual(p.returncode, 0, "EXPECTED_PG_REJECTION_MISSING")
        return p.stdout, p.stderr

    def exercise(self, image):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED_FOR_PG_DUAL")
        name="lf-ig-writer-"+uuid.uuid4().hex[:10]
        p=subprocess.run(["docker","run","-d","--rm","--name",name,
                          "-e","POSTGRES_PASSWORD=postgres",image],
                          capture_output=True,text=True,timeout=140)
        self.assertEqual(p.returncode,0,p.stderr[-2000:])
        try:
            for _ in range(75):
                r=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                                 capture_output=True,text=True,timeout=8)
                if r.returncode==0: break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            self.connected(name)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=35)

    def connected(self,name):
        setup=(
        """CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
        CREATE ROLE service_role NOLOGIN; CREATE ROLE anon NOLOGIN;
        CREATE ROLE authenticated NOLOGIN;
        CREATE TABLE public.lf_operation_execution(
         execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
         status text,manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
         created_at timestamptz NOT NULL DEFAULT clock_timestamp());
        CREATE TABLE public.lf_operation_execution_steps(
         execution_id text,step_id text,step_order integer,status text,evidence_ref text,
         evidence_payload jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
         PRIMARY KEY(execution_id,step_id));
        CREATE TABLE public.lf_ig_native_chat_receipt_v1(
         execution_id text NOT NULL,seq integer NOT NULL CHECK(seq BETWEEN 1 AND 3),
         kind text NOT NULL CHECK(kind IN ('REQUEST','EXECUTOR','JUDGE')),
         raw_text text NOT NULL,raw_sha256 text NOT NULL,
         prev_sha256 text NOT NULL,chain_sha256 text NOT NULL,
         writer_receipt_ref text NOT NULL,writer_receipt_sha256 text NOT NULL,
         recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
         PRIMARY KEY(execution_id,seq));
        CREATE FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1()
         RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
         SET search_path TO 'pg_catalog','public' AS $$
         BEGIN RAISE EXCEPTION 'B09_RECEIPT_IMMUTABLE' USING ERRCODE='23514'; END $$;
        CREATE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1
         BEFORE UPDATE OR DELETE ON public.lf_ig_native_chat_receipt_v1
         FOR EACH ROW EXECUTE FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1();
        REVOKE ALL ON public.lf_ig_native_chat_receipt_v1
          FROM PUBLIC,anon,authenticated,service_role;
        """
        + f"""INSERT INTO public.lf_operation_execution(
          execution_id,operation_code,target_type,target_code,status,manifest)
         VALUES({q(RUN)},'EJECUCION_PERFIL_LF','PERFIL',{q(PROFILE)},
          'IN_PROGRESS','{{"executor_mode":"GPT_NATIVE",
          "executor_provider":"OPENAI_CHATGPT_NATIVE",
          "governed_repair_write":true,"no_promotion":true}}'::jsonb);
         INSERT INTO public.lf_operation_execution_steps
          (execution_id,step_id,step_order,status,evidence_ref,evidence_payload)
         VALUES
         ({q(RUN)},'input_validate',40,'STEP_PASS_WITH_EVIDENCE','supabase://fixture/step40',
          '{{"scope_authority_packet_sha256":"sha256:{SCOPE}"}}'::jsonb),
         ({q(RUN)},'execute_profile',50,'STEP_PASS_WITH_EVIDENCE',{q(REF)},
          '{{"profile_output":{{"profile_pack_id":"{SCHEMA}","status":"SYSTEMIC_REPAIR_SPEC"}}}}'::jsonb),
         ({q(RUN)},'output_validate',60,'STEP_PASS_WITH_EVIDENCE','supabase://fixture/step60',
          '{{"deterministic_validation":{{"status":"PASS",
          "source_bound_validation":{{"schema":"{EVAL}"}}}},
          "output_contract_result":"PASS"}}'::jsonb);
         UPDATE public.lf_operation_execution_steps SET evidence_payload=
          jsonb_set(evidence_payload,'{{raw_output_sha256}}',
           to_jsonb(encode(extensions.digest(
            convert_to((evidence_payload->'profile_output')::text,'UTF8'),
            'sha256'),'hex'))) WHERE execution_id={q(RUN)}
              AND step_id='execute_profile';
         UPDATE public.lf_operation_execution_steps SET evidence_payload=
          jsonb_set(evidence_payload,'{{raw_output_sha256}}',
           to_jsonb((SELECT evidence_payload->>'raw_output_sha256'
              FROM public.lf_operation_execution_steps
              WHERE execution_id={q(RUN)} AND step_id='execute_profile')))
           WHERE execution_id={q(RUN)} AND step_id='output_validate';
         """
        )
        verifier=STEP70.read_text(encoding="utf8")
        start=verifier.index("CREATE FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(")
        end=verifier.index("REVOKE ALL ON FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(",start)
        setup+="\n"+verifier[start:end]
        self.run_sql(name,setup)
        # Direct insert is explicitly denied to the non-owner DB role
        negative=f"""BEGIN;
        SET LOCAL ROLE service_role;
        INSERT INTO public.lf_ig_native_chat_receipt_v1 DEFAULT VALUES;
        ROLLBACK;"""
        out,err=self.run_sql(name,negative,success=False)
        self.assertIn("permission denied",err.lower())
        source=MIG.read_text(encoding="utf8")
        self.assertIn("LF_NATIVE_CHAT_WRITER_FUNCTION_PREEXISTS_DRIFT",source)
        self.assertIn("LF_NATIVE_CHAT_WRITER_IMMUTABILITY_TRIGGER_DRIFT",source)
        ddl=clean_ddl(source)
        body=f"""BEGIN;
        {ddl}
        SELECT 'ACL_DIRECT|'||has_table_privilege('service_role',
          'public.lf_ig_native_chat_receipt_v1','INSERT')::text;
        SELECT 'ACL_RPC|'||has_function_privilege('service_role',
          'public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)','EXECUTE')::text;
        SELECT 'ACL_ANON|'||has_function_privilege('anon',
          'public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)','EXECUTE')::text;
        SELECT 'NONCE_FORGED|'||({writer('REQUEST',q('{"nonce":"client-forged"}'))}->>'blocking_code');
        SELECT 'COUNT_BEFORE|'||count(*) FROM public.lf_ig_native_chat_receipt_v1;
        SELECT 'REQ|'||({writer('REQUEST',q('{}'))}->>'status');
        SELECT 'REQ_RETRY|'||({writer('REQUEST',q('{}'))}->>'status');
        SELECT 'NONCE_SERVER|'||(SELECT ((raw_text::jsonb)->>'nonce') ~ '^[a-f0-9]{{48}}$'
           FROM public.lf_ig_native_chat_receipt_v1 WHERE seq=1)::text;
        SELECT 'JUDGE_EARLY|'||({writer('JUDGE',judge())}->>'blocking_code');
        SELECT 'EXEC|'||({writer('EXECUTOR',EXEC)}->>'status');
        SELECT 'EXEC_RETRY|'||({writer('EXECUTOR',EXEC)}->>'status');
        SELECT 'JUDGE_EQUAL_CONTEXT|'||({writer('JUDGE',judge("context://fixture/producer-real"))}->>'blocking_code');
        SELECT 'JUDGE|'||({writer('JUDGE',judge())}->>'status');
        SELECT 'JUDGE_RETRY|'||({writer('JUDGE',judge())}->>'status');
        SELECT 'VERIFIER|'||(public.lf_profile_step70_clean_eval_context_verify_v1(
          {q(RUN)},jsonb_build_object(
           'review_mode','INDEPENDENT_EVAL_CONTEXT',
           'candidate_sha256',(SELECT evidence_payload->>'raw_output_sha256'
             FROM public.lf_operation_execution_steps WHERE step_id='execute_profile'),
           'scope_packet_sha256',{q(SCOPE)},
           'judge_v3_evidence',(SELECT (raw_text::jsonb)->'review_payload'
             FROM public.lf_ig_native_chat_receipt_v1 WHERE seq=3)
          ))->>'status');
        SELECT 'COUNT_AFTER|'||count(*) FROM public.lf_ig_native_chat_receipt_v1;
        SELECT 'CHAIN_VALID|'||(SELECT bool_and(
          writer_receipt_sha256=encode(extensions.digest(
            convert_to(writer_receipt_ref||'|'||raw_sha256,'UTF8'),'sha256'),'hex')
          AND chain_sha256=encode(extensions.digest(convert_to(
            'LF_NATIVE_CHAT_EVENT_V1|'||execution_id||'|'||seq||'|'||kind||'|'||
             raw_sha256||'|'||prev_sha256||'|'||writer_receipt_sha256,
            'UTF8'),'sha256'),'hex'))
          FROM public.lf_ig_native_chat_receipt_v1)::text;
        SAVEPOINT seq_tamper;
        SET LOCAL session_replication_role='replica';
        UPDATE public.lf_ig_native_chat_receipt_v1 SET seq=4 WHERE seq=2;
        SET LOCAL session_replication_role='origin';
        SELECT 'TAMPER_SEQ|'||({writer('JUDGE',judge())}->>'blocking_code');
        ROLLBACK TO SAVEPOINT seq_tamper;
        SAVEPOINT hash_tamper;
        SET LOCAL session_replication_role='replica';
        UPDATE public.lf_ig_native_chat_receipt_v1 SET raw_sha256=repeat('e',64)
          WHERE seq=2;
        SET LOCAL session_replication_role='origin';
        SELECT 'TAMPER_HASH|'||({writer('JUDGE',judge())}->>'blocking_code');
        ROLLBACK TO SAVEPOINT hash_tamper;
        SELECT 'IMMU_TRIGGER|'||(SELECT count(*)=1 FROM pg_trigger
          WHERE tgrelid='public.lf_ig_native_chat_receipt_v1'::regclass
            AND tgname='lf_ig_native_chat_receipt_no_mutation_v1' AND tgenabled='O')::text;
        ROLLBACK;"""
        # Tampering scenario uses SQL table CHECK seq 1..3; change seq 2->3 would
        # conflict with positive JUDGE seq3, so shift seq3 to 2? Instead reorder kind
        # on row 2; it does not violate PK/check and strictly breaks sequencing.
        body=body.replace("SET seq=4 WHERE seq=2","SET kind='JUDGE' WHERE seq=2")
        out,err=self.run_sql(name,body)
        for case in (
          "ACL_DIRECT|false","ACL_RPC|true","ACL_ANON|false",
          "NONCE_FORGED|LF_NATIVE_CHAT_WRITER_CALLER_PROVENANCE_DRIFT",
          "COUNT_BEFORE|0","REQ|RECEIPT_APPENDED",
          "REQ_RETRY|ALREADY_RECORDED","NONCE_SERVER|true",
          "JUDGE_EARLY|LF_NATIVE_CHAT_WRITER_SEQUENCE_DRIFT",
          "EXEC|RECEIPT_APPENDED","EXEC_RETRY|ALREADY_RECORDED",
          "JUDGE_EQUAL_CONTEXT|LF_NATIVE_CHAT_WRITER_JUDGE_CONTEXT_DRIFT",
          "JUDGE|RECEIPT_APPENDED","JUDGE_RETRY|ALREADY_RECORDED",
          "VERIFIER|CLEAN_CONTEXT_EVAL_VERIFIED","COUNT_AFTER|3",
          "CHAIN_VALID|true","TAMPER_SEQ|LF_NATIVE_CHAT_WRITER_SEQUENCE_DRIFT",
          "TAMPER_HASH|LF_NATIVE_CHAT_WRITER_RAW_OR_WRITER_SHA_DRIFT",
          "IMMU_TRIGGER|true",
        ):
            self.assertIn(case,out,case+"\n"+out[-2300:])
        back,_=self.run_sql(name,
          "SELECT to_regprocedure('public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)') IS NULL;")
        self.assertEqual(back.strip(),"t","PG_TRANSACTION_DDL_NOT_ROLLED_BACK")
        back,_=self.run_sql(name,"SELECT count(*) FROM public.lf_ig_native_chat_receipt_v1;")
        self.assertEqual(back.strip(),"0","PG_TRANSACTION_EVENTS_NOT_ROLLED_BACK")

if __name__=="__main__": unittest.main()
