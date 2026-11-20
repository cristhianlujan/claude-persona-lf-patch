#!/usr/bin/env python3
"""B09 phase 1 Step70/G15 documentary SHA branch: PG17.6 and PG18.7 fail-closed lab.
Never accesses Supabase; synthetic fixture proves migration is reversible and
cannot bypass official missing writer/nonce. Does NOT prove an E2E real RUN.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle"
SLICE = BASE / "pg18_live_object_slice_baseline.sql"
UPSTREAM = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
STEP70_PREIMAGE = BASE / "pg18_step70_bridge_live_preimage.sql"
SCOPE = ROOT / "supabase/migrations/20261113083527_lf_router_scope_receipt_consumer_v2.sql"
RECEIVER = ROOT / "supabase/migrations/20261113143831_lf_ig_native_chat_sha_receiver_v1.sql"
UP = ROOT / "supabase/migrations/20261113220000_lf_ig_native_chat_step70_g15_documental_v1.sql"
DOWN = BASE / "rollback_lf_ig_native_chat_step70_g15_documental_v1.sql"
EID = "EXEC-PROFILE-GATE2-B09DOCUMENTAL00001"

def quote(x):
    return "'" + str(x).replace("'", "''") + "'"

class B09DocumentalStep70G15(unittest.TestCase):
    def test_lab(self):
        self.assertIsNotNone(shutil.which("docker"), "B09_DOCUMENTAL_DOCKER_NOT_AVAILABLE")
        for file in (SLICE, UPSTREAM, STEP70_PREIMAGE, SCOPE, RECEIVER, UP, DOWN):
            self.assertTrue(file.is_file(), "B09_DOCUMENTAL_SOURCE_MISSING " + str(file))
        for image, version in (("postgres:17.6", "170006"), ("postgres:18", "180007")):
            self.run_image(image, version)

    def run_image(self, image, version):
        name = "lf-b09-doc-" + uuid.uuid4().hex[:12]
        started = subprocess.run(["docker","run","-d","--rm","--name",name,
            "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=240)
        self.assertEqual(started.returncode,0,"B09_DOCUMENTAL_DOCKER_START_FAILED "+started.stderr)
        try:
            def sql(code, error=None, timeout=300):
                x=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t","-q",
                    "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                    input=code,capture_output=True,text=True,timeout=timeout)
                if error:
                    self.assertNotEqual(x.returncode,0,"B09_DOCUMENTAL_NEGATIVE_ACCEPTED")
                    self.assertIn(error,x.stderr,"B09_DOCUMENTAL_UNEXPECTED_ERROR "+x.stderr[-1500:])
                else:
                    self.assertEqual(x.returncode,0,"B09_DOCUMENTAL_SQL_ERROR "+x.stderr[-2700:])
                return x.stdout.strip()
            for _ in range(50):
                if subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                                  capture_output=True,timeout=10).returncode==0:break
                time.sleep(1)
            else:self.fail("B09_DOCUMENTAL_POSTGRES_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"),version,"B09_DOCUMENTAL_VERSION_MISMATCH")
            sql(SLICE.read_text(encoding="utf-8"),timeout=450)
            train="EXEC-DB-TRAIN-PR3803-20261113030000-R43379990009"
            sql("""INSERT INTO public.lf_operation_execution
                (execution_id,operation_code,target_type,target_code,target_repo,target_path,
                 status,request_sha256,manifest,idempotency_key,created_by_execution_id)
                VALUES ("""+",".join([
                  quote(train),quote("ACTUALIZACION_DB_LF"),quote("MIGRATION"),
                  quote("20261113030000_lf_ig_rule_lifecycle_writer_v2"),
                  quote("cristhianlujan/claude-persona-lf-patch"),
                  quote("supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"),
                  quote("IN_PROGRESS"),quote("f"*64),
                  quote(json.dumps({"producer":"lf-migration-merge-train","pr":3803,
                      "train_run_id":"43379990009","head_sha":"e"*40,
                      "router_authority_receipt":{"schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                       "operation_code":"ACTUALIZACION_DB_LF","target_repo":"cristhianlujan/claude-persona-lf-patch",
                       "target_code":"20261113030000_lf_ig_rule_lifecycle_writer_v2",
                       "target_path":"supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql",
                       "route_eligibility_only":True,"scope_attested":False}}))+"::jsonb",
                  quote("train:20261113030000:"+"e"*40),quote("LF-MIGRATION-TRAIN-RUN-43379990009")])+");")
            sql(UPSTREAM.read_text(encoding="utf-8"),timeout=450)
            sql(STEP70_PREIMAGE.read_text(encoding="utf-8"),timeout=240)
            sql(SCOPE.read_text(encoding="utf-8"),timeout=300)
            if sql("SELECT to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL;")=="t":
                sql("""CREATE FUNCTION public.lf_record_profile_execution_step_v1(
                    text,text,text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $fixture$
                    SELECT jsonb_build_object('status','BLOCKED','blocking_code','B09_FIXTURE_NO_EFFECTS') $fixture$;""")
            sql(RECEIVER.read_text(encoding="utf-8"),timeout=300)
            md5=lambda fn:sql("SELECT md5(pg_get_functiondef('public."+fn+"'::regprocedure));")
            old70=md5("lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)")
            old15=md5("lf_ig_g15_motor_temporary_v1(jsonb)")
            self.assertEqual(old70,"78cb1b8fab6975f4539a79baa2ab11fd")
            self.assertEqual(old15,"eb1779e3d958d26d56a20f22ed717235")
            sql(UP.read_text(encoding="utf-8"),timeout=300)
            self.assertNotEqual(md5("lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)"),old70)
            self.assertNotEqual(md5("lf_ig_g15_motor_temporary_v1(jsonb)"),old15)
            self.assertEqual(sql("""SELECT has_function_privilege('anon',
              'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)','EXECUTE');"""),"f")
            self.assertEqual(sql("""SELECT has_function_privilege('authenticated',
              'public.lf_ig_g15_motor_temporary_v1(jsonb)','EXECUTE');"""),"f")
            manifest={"executor_mode":"GPT_NATIVE","executor_provider":"OPENAI_CHATGPT_NATIVE",
                 "read_only":False,"no_write":False,"no_promotion":False}
            sql("INSERT INTO public.lf_operation_execution "
                "(execution_id,operation_code,target_type,target_code,status,request_sha256,"
                "idempotency_key,manifest,created_by_execution_id) VALUES ("+
                ",".join([quote(EID),quote("EJECUCION_PERFIL_LF"),quote("PERFIL"),
                quote("PERFIL-PRODUCT-DIRECTOR-LF"),quote("IN_PROGRESS"),quote("a"*64),
                quote("b09-doc:"+EID),quote(json.dumps(manifest))+"::jsonb",quote(EID)])+");")
            val={"status":"PASS","validator_status":"PASS",
                 "review_mode":"SAME_LLM_SEPARATE_CHAT",
                 "verdict":"PASS_SEMANTIC_COMPENSATED_SAME_MODEL",
                 "producer_independence_proven":False,
                 "reviewer_model_independence_proven":False,
                 "vendor_model_provenance_verified":False,
                 "reviewer_is_producer":False,"effect_authority":False,
                 "model_call_count":1,"candidate_sha256":"a"*64,
                 "scope_packet_sha256":"b"*64,"provider_receipt_ref":"fixture://not-attested",
                 "chain_tip_sha256":"c"*64,"producer_prompt_sha256":"d"*64,
                 "reviewer_prompt_sha256":"e"*64,
                 "result":{"unsupported_claims":[],"blocking_codes":[]}}
            def step(payload):
                return json.loads(sql("SELECT public.lf_profile_native_bridge_record_semantic_v1("+
                   quote(EID)+","+quote(json.dumps(payload))+"::jsonb,'fixture://step70',"+
                   quote(EID)+")::text;"))
            self.assertEqual(step(val)["blocking_code"],"LF_STEP70_SHA_OFFICIAL_WRITER_BINDING_MISSING")
            forged=dict(val,producer_independence_proven=True)
            self.assertEqual(step(forged)["blocking_code"],"LF_STEP70_SHA_DOCUMENTAL_RISK_MODE_INVALID")
            forged=dict(val,review_mode="CURRENT_CONTEXT_REVIEW")
            self.assertEqual(step(forged)["blocking_code"],"LF_STEP70_NATIVE_SELF_REVIEW_FORBIDDEN")
            forged=dict(val,verdict="PASS_INDEPENDENT_SEMANTIC")
            self.assertEqual(step(forged)["blocking_code"],"LF_STEP70_SHA_DOCUMENTAL_RISK_MODE_INVALID")
            self.assertEqual(sql("SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(EID)+";"),"0")
            g15=lambda d:json.loads(sql("SELECT public.lf_ig_g15_motor_temporary_v1("+
                quote(json.dumps(d))+"::jsonb)::text;"))
            self.assertEqual(g15({})["blocking_code"],"G15_MOTOR_7_OF_7_NOT_EVIDENCED")
            valid={k:{"status":"VERIFIED","sha256":"f"*64,"evidence_ref":"fixture://NOT_ATTESTED"} for k in
                 ("B02_RUN_SCOPE","B03_RUN_EFFECTS","B06_OWNER","B07_SCHEMA","B08_IDENTITY","B09_E2E","B12_LEGACY")}
            self.assertEqual(g15(valid)["blocking_code"],"G15_MOTOR_CRYPTOGRAPHIC_SIGNATURES_NOT_VERIFIED")
            valid["B09_E2E"].update({"risk_mode":"SAME_LLM_SEPARATE_CHAT_SHA256_DOCUMENTAL","execution_id":EID})
            x=g15(valid)
            self.assertEqual(x["status"],"NO_GO_MOTOR")
            self.assertEqual(x["blocking_code"],"G15_B09_DOCUMENTAL_OFFICIAL_WRITER_NOT_READY")
            self.assertIs(x["b09_documental_accepted"],False)
            print("PASS_B09_DOCUMENTAL_STEP70_G15_FAIL_CLOSED_"+version,flush=True)
            sql(DOWN.read_text(encoding="utf-8"),timeout=300)
            self.assertEqual(md5("lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)"),old70)
            self.assertEqual(md5("lf_ig_g15_motor_temporary_v1(jsonb)"),old15)
            self.assertEqual(sql("SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(EID)+";"),"0")
            self.assertEqual(sql("SELECT to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NOT NULL;"),"t")
            print("PASS_B09_DOCUMENTAL_ROLLBACK_PREIMAGE_"+version,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=90)

if __name__=="__main__":
    unittest.main()
