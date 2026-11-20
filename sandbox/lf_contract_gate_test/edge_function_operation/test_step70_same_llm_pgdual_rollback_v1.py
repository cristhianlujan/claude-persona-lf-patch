"""Step70 same-LLM separate-call contract PG17.6 / PG18.7 ROLLBACK.

Tests are offline and deliberately DO NOT simulate a real LLM provider call.
"""
import json
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
FIX=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixture_judge_independence_live_pgdual_v1.sql"
PRE=ROOT/"supabase/migrations/20261114203100_lf_judge_independence_skill_selector_contract_v1.sql"
MIG=ROOT/"supabase/migrations/20261114210500_lf_step70_separate_call_unattested_preflight_and_findings_readback_v1.sql"
ID="EXEC-PROFILE-GATE2-TESTSAMECALL00112233"
H40="b"*64
H50="a"*64

def sample_receipt():
    return {
      "schema_version":"LF_STEP70_SAME_LLM_SEPARATE_CALL_RECEIPT_V1",
      "receipt_ref":"actions://reviewer/run/200/receipt",
      "execution_id":ID,"model_id":"GPT-6",
      "model_call_id":"reviewer-native-call-200200",
      "producer_call_ref":"actions://producer/run/100/raw",
      "reviewer_call_ref":"actions://reviewer/run/200/raw",
      "prompt_sha256":"c"*64,"producer_prompt_sha256":"d"*64,
      "schema_id":"LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1",
      "producer_schema_id":"PROFILE_PRODUCT_DIRECTION_SPEC",
      "eval_id":"LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1",
      "producer_eval_id":"PROFILE_OUTPUT_VALIDATION_RESULT_V1",
      "eval_status":"PASS","model_call_count":1,
      "candidate_sha256":H50,"scope_packet_sha256":H40,
      "decision_body":{"verdict":"PASS_INDEPENDENT_SEMANTIC"},
      "provider_attestation":True
    }

class Step70SameLlmPgDual(unittest.TestCase):
  def test_pg17_6(self):self.run_db("postgres:17.6","170006")
  def test_pg18_7(self):self.run_db("postgres:18.7","180007")

  def run_db(self,image,version):
    name="lf-same-llm-"+uuid.uuid4().hex[:11]
    r=subprocess.run(["docker","run","-d","--rm","--name",name,"-e",
       "POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=150)
    self.assertEqual(r.returncode,0,r.stderr[-1800:])
    try:
      for _ in range(80):
        check=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
            capture_output=True,text=True,timeout=10)
        if check.returncode==0:
          logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
          if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
            break
        time.sleep(1)
      else:self.fail("PG_NOT_READY")
      def sql(body):
        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
              "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
              input=body,text=True,capture_output=True,timeout=160)
        self.assertEqual(p.returncode,0,p.stderr[-7800:])
        return p.stdout.strip()
      self.assertTrue(sql("SHOW server_version_num;").startswith(version))
      sql(FIX.read_text(encoding="utf8"))
      sql("CREATE ROLE service_role NOLOGIN;")
      sql(PRE.read_text(encoding="utf8"))
      self.assertEqual(sql("SELECT count(*) FROM public.lf_profile_semantic_independence_finding_v1;"),"3")
      prior=sql("SELECT md5(string_agg(s.evidence_payload::text,',' ORDER BY s.execution_id,s.step_id)) FROM public.lf_operation_execution_steps s;")
      # Temporary 9/11 mock: real sources are never modified or re-used.
      sql(f"""INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status)
         VALUES('{ID}','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS');
         INSERT INTO public.lf_operation_execution_steps VALUES
         ('{ID}','input_validate',40,'STEP_PASS_WITH_EVIDENCE','{{"scope_authority_packet_sha256":"{H40}"}}'::jsonb,'fixture://40'),
         ('{ID}','execute_profile',50,'STEP_PASS_WITH_EVIDENCE','{{"raw_output_sha256":"{H50}"}}'::jsonb,'actions://producer/runs/100/raw'),
         ('{ID}','output_validate',60,'STEP_PASS_WITH_EVIDENCE','{{"output_contract_result":"PASS","deterministic_validation":{{"source_bound_validation":{{"schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","source_refs":{{"schema":"profiles/product_director_lf/schemas/product_direction_spec.schema.json"}}}}}}}}'::jsonb,'fixture://60');""")
      migration=MIG.read_text(encoding="utf8")
      self.assertTrue(migration.startswith("-- LF sandbox"))
      body=migration.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
      escaped=json.dumps(sample_receipt(),separators=(",",":")).replace("'","''")
      result=sql("BEGIN;\n"+body+"\n"+
       """DO $test$ DECLARE v integer;BEGIN
       SELECT count(*) INTO v FROM public.v_lf_profile_step70_independence_readback_v1
        WHERE separate_finding_code='JUDGE_INDEPENDENCE_NOT_PROVEN'
         AND finding_stored_outside_original_step;
       IF v<>6 THEN RAISE EXCEPTION 'LEGACY_FINDING_READBACK_COUNT_%',v; END IF;
       IF (SELECT count(*) FROM public.v_lf_profile_step70_independence_readback_v1
        WHERE independent_semantic_receipt_ref IS NOT NULL)<>0
       THEN RAISE EXCEPTION 'FORGED_INDEPENDENT_RECEIPT'; END IF;
       END $test$;
       """+f"SELECT public.lf_profile_step70_separate_call_preflight_v1('{ID}',NULL)->>'status';\n"+
       f"SELECT public.lf_profile_step70_separate_call_preflight_v1('{ID}','{escaped}'::jsonb)->>'status';\n"+
       "ROLLBACK;\nSELECT to_regclass('public.v_lf_profile_step70_independence_readback_v1') IS NULL;")
      self.assertEqual(result.splitlines()[-3:],[
         "JUDGE_INDEPENDENCE_NOT_PROVEN",
         "RECEIPT_FORMAT_VALID_MODEL_CALL_NOT_ATTESTED","t"])
      final=sql("SELECT md5(string_agg(s.evidence_payload::text,',' ORDER BY s.execution_id,s.step_id)) FROM public.lf_operation_execution_steps s WHERE s.execution_id<>'"+ID+"';")
      self.assertEqual(final,prior)
      print("PASS_LF_STEP70_SEPARATE_CALL_CONTRACT_NO_FALSE_ATTESTATION_PG"+version+"_ROLLBACK",flush=True)
    finally:
      subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=60)

if __name__=="__main__":unittest.main()
