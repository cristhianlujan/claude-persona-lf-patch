#!/usr/bin/env python3
"""B09 governed receiver: real isolated PG17.6/18.7 Docker, never Supabase.
Fixtures directly inserted as SQL by test superuser DO NOT certify native model
provenance or the official writer. The existing Step70 still MUST BLOCK.
"""
import hashlib
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle"
UPSTREAM = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
STEP70_PREIMAGE = BASE / "pg18_step70_bridge_live_preimage.sql"
SCOPE_3807 = ROOT / "supabase/migrations/20261113083527_lf_router_scope_receipt_consumer_v2.sql"
UP = ROOT / "supabase/migrations/20261113143831_lf_ig_native_chat_sha_receiver_v1.sql"
DOWN = BASE / "rollback_lf_ig_native_chat_sha_receiver_v1.sql"
SLICE = BASE / "pg18_live_object_slice_baseline.sql"
TABLE = "public.lf_ig_native_chat_receipt_v1"
RUN = "EXEC-PROFILE-GATE2-B09GOVERNEDPOS0001"
FOREIGN = "EXEC-PROFILE-GATE2-B09FOREIGN00002"
OLD = "EXEC-PROFILE-GATE2-B09COMPLETE0003"
ZERO = "0" * 64

def sha(v):
    return hashlib.sha256(v.encode("utf-8")).hexdigest()

def quote(v):
    return "'" + str(v).replace("'", "''") + "'"

def jq(v):
    return quote(json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False))+"::jsonb"

def make_event(run,idx,kind,payload,prior):
    raw=json.dumps(payload,sort_keys=True,separators=(",",":"),ensure_ascii=False)
    rh=sha(raw)
    wh=sha("FIXTURE_NOT_OFFICIAL_WRITER")
    ch=sha("|".join(("LF_NATIVE_CHAT_EVENT_V1",run,str(idx),kind,rh,prior,wh)))
    return (run,idx,kind,raw,rh,prior,ch,"fixture://NOT_AUTHENTICATED",wh)

def insert_event(e):
    fields=("execution_id","seq","kind","raw_text","raw_sha256","prev_sha256",
            "chain_sha256","writer_receipt_ref","writer_receipt_sha256")
    vals=[str(x) if n==1 else quote(x) for n,x in enumerate(e)]
    return "INSERT INTO "+TABLE+"("+",".join(fields)+") VALUES("+",".join(vals)+");"

class B09NativeShaGoverned(unittest.TestCase):
    def run_test(self,image,version_expected):
        self.assertIsNotNone(shutil.which("docker"),"NOT_TESTED_DOCKER_MISSING")
        for p in (SLICE,UPSTREAM,STEP70_PREIMAGE,SCOPE_3807,UP,DOWN):
            self.assertTrue(p.is_file(),"SOURCE_MISSING "+str(p))
        name="lf-b09-gov-"+uuid.uuid4().hex[:12]
        start=subprocess.run(["docker","run","-d","--rm","--name",name,
                              "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",
                              image],capture_output=True,text=True,timeout=240)
        self.assertEqual(start.returncode,0,"DOCKER_START_FAILED "+start.stderr)
        try:
            def sql(raw,should_fail=None,timeout=360):
                x=subprocess.run(["docker","exec","-i",name,"psql","-X",
                    "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres",
                    "-A","-t","-q"],input=raw,capture_output=True,text=True,timeout=timeout)
                if should_fail is not None:
                    self.assertNotEqual(x.returncode,0,"SQL_NEGATIVE_PASSED "+raw[:120])
                    self.assertIn(should_fail,x.stderr[-4000:],x.stderr[-4000:])
                else:
                    self.assertEqual(x.returncode,0,"SQL_FAILED "+x.stderr[-3500:])
                return x.stdout.strip()
            for _ in range(50):
                ok=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                                  capture_output=True,timeout=15)
                if ok.returncode==0:break
                time.sleep(1)
            else:self.fail("POSTGRES_NOT_READY")
            v=sql("SHOW server_version_num;")
            self.assertEqual(v,version_expected,"PG_EXACT_VERSION_NOT_REPRODUCED")
            # Same live-object schema slice used by the canonical #3803 tests.
            sql(SLICE.read_text(encoding="utf-8"),timeout=450)
            train_id="43379990009"
            code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            repo="cristhianlujan/claude-persona-lf-patch"
            target="supabase/migrations/"+code+".sql"
            train="EXEC-DB-TRAIN-PR3803-20261113030000-R"+train_id
            manifest={"producer":"lf-migration-merge-train","pr":3803,
                      "train_run_id":train_id,"head_sha":"e"*40,
                      "router_authority_receipt":{
                        "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                        "operation_code":"ACTUALIZACION_DB_LF","target_repo":repo,
                        "target_code":code,"target_path":target,
                        "route_eligibility_only":True,"scope_attested":False}}
            sql("""INSERT INTO public.lf_operation_execution
               (execution_id,operation_code,target_type,target_code,target_repo,
                target_path,status,request_sha256,manifest,idempotency_key,
                created_by_execution_id) VALUES ("""+
                ",".join([quote(train),quote("ACTUALIZACION_DB_LF"),quote("MIGRATION"),
                   quote(code),quote(repo),quote(target),quote("IN_PROGRESS"),
                   quote("f"*64),jq(manifest),quote("train:20261113030000:"+"e"*40),
                   quote("LF-MIGRATION-TRAIN-RUN-"+train_id)])+");")
            sql(UPSTREAM.read_text(encoding="utf-8"),timeout=450)
            sql(STEP70_PREIMAGE.read_text(encoding="utf-8"),timeout=240)
            sql(SCOPE_3807.read_text(encoding="utf-8"),timeout=300)
            # The live-object slice omits the full profile step writer. Create
            # ONLY a blocked/no-effect signature fixture in throwaway Docker;
            # production preflight still requires the existing canonical writer.
            if sql("SELECT to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL;")=="t":
                sql("""CREATE FUNCTION public.lf_record_profile_execution_step_v1(
                    p_execution_id text,p_step_id text,p_evidence_ref text,
                    p_evidence_payload jsonb,p_actor_execution_id text)
                    RETURNS jsonb LANGUAGE sql AS $b09stub$
                    SELECT jsonb_build_object('status','BLOCKED',
                        'blocking_code','B09_TEST_STUB_NO_WRITER_EFFECTS') $b09stub$;""")
                print("B09_TEST_FIXTURE_CANONICAL_WRITER_SIGNATURE_ONLY_NO_EFFECTS",flush=True)
            step70_before=sql("SELECT md5(pg_get_functiondef('public."
                "lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));")
            g15_before=sql("SELECT md5(pg_get_functiondef('public."
                "lf_ig_g15_motor_temporary_v1(jsonb)'::regprocedure));")
            self.assertEqual(step70_before,"78cb1b8fab6975f4539a79baa2ab11fd")
            self.assertEqual(g15_before,"eb1779e3d958d26d56a20f22ed717235")
            self.assertEqual(sql("SELECT to_regprocedure("
                "'public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL;"),"t")
            sql(UP.read_text(encoding="utf-8"),timeout=200)
            self.assertEqual(sql("SELECT to_regprocedure("
                "'public.lf_ig_verified_native_provider_receipt_v1(text)') IS NOT NULL;"),"t")
            self.assertEqual(sql("SELECT has_function_privilege('service_role',"
                "'public.lf_ig_verified_native_provider_receipt_v1(text)','EXECUTE');"),"t")
            self.assertEqual(sql("SELECT has_function_privilege('anon',"
                "'public.lf_ig_verified_native_provider_receipt_v1(text)','EXECUTE');"),"f")
            self.assertEqual(sql("SELECT has_table_privilege('service_role',"
                "'"+TABLE+"','INSERT');"),"f")
            sql("BEGIN; SET LOCAL ROLE anon; SELECT public."
                "lf_ig_verified_native_provider_receipt_v1("+quote(RUN)+"); ROLLBACK;",
                should_fail="permission denied")
            print("PASS_B09_GOVERNED_RECEIVER_UP_AND_ACL_"+v,flush=True)

            def add_run(run,status,manifest_override=None,op="EJECUCION_PERFIL_LF"):
                m={"executor_mode":"GPT_NATIVE","executor_provider":"OPENAI_CHATGPT_NATIVE",
                   "read_only":False,"no_write":False,"no_promotion":False}
                if manifest_override:m.update(manifest_override)
                sql("INSERT INTO public.lf_operation_execution"
                    "(execution_id,operation_code,target_type,target_code,status,"
                    "request_sha256,idempotency_key,manifest,created_by_execution_id)"
                    " VALUES ("+",".join((quote(run),quote(op),quote("PERFIL"),
                    quote("PERFIL-PRODUCT-DIRECTOR-LF"),quote(status),
                    quote("b"*64),quote("b09-governed:"+run),jq(m),quote(run)))+");")
            add_run(RUN,"IN_PROGRESS")
            add_run(FOREIGN,"IN_PROGRESS",{"executor_provider":"NOT_NATIVE"})
            add_run(OLD,"COMPLETED")
            reader=lambda ex:"SELECT public.lf_ig_verified_native_provider_receipt_v1("+quote(ex)+")::text;"
            blocked=json.loads(sql(reader(FOREIGN)).splitlines()[-1])
            self.assertEqual(blocked["blocking_code"],"B09_RUN_NOT_ELIGIBLE")
            blocked=json.loads(sql(reader(OLD)).splitlines()[-1])
            self.assertEqual(blocked["blocking_code"],"B09_RUN_NOT_ELIGIBLE")
            self.assertEqual(json.loads(sql(reader(RUN)).splitlines()[-1])["blocking_code"],"B09_CHAIN_INCOMPLETE")
            producer_prompt=sha("VERSIONED_PRODUCER_PROMPT")
            judge_prompt=sha("VERSIONED_DISTINCT_JUDGE_INSTRUCTIONS")
            shared={"execution_id":RUN,"nonce":"test-b09-nonce-unique-0001",
                    "candidate_sha256":sha("candidate"),"scope_packet_sha256":sha("scope"),
                    "producer_prompt_sha256":producer_prompt}
            prod_chat="https://chatgpt.com/c/producer-test-placeholder"
            judge_chat="https://chatgpt.com/c/judge-test-placeholder"
            raw=[
              ("REQUEST",{**shared,"stage":"REQUEST"}),
              ("EXECUTOR",{**shared,"stage":"EXECUTOR","executor_chat_ref":prod_chat,
                 "provider_receipt_ref":"native-chat://UNVERIFIED-TEST-REF"}),
              ("JUDGE",{**shared,"stage":"JUDGE","executor_chat_ref":prod_chat,
                 "judge_chat_ref":judge_chat,"review_mode":"SAME_LLM_SEPARATE_CHAT",
                 "reviewer_prompt_sha256":judge_prompt})
            ]
            prev=ZERO;events=[]
            for n,(kind,data) in enumerate(raw,1):
                row=make_event(RUN,n,kind,data,prev);events.append(row);prev=row[6]
                sql(insert_event(row))
            good=json.loads(sql(reader(RUN)).splitlines()[-1])
            self.assertEqual(good["status"],"SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED")
            self.assertEqual(good["chain_tip_sha256"],events[-1][6])
            for key in ("writer_identity_verified","vendor_model_provenance_verified",
                "reviewer_model_independence_proven","effect_authority","downstream_execution_allowed"):
                self.assertIs(good[key],False,key)
            self.assertNotEqual(good["status"],"CRYPTOGRAPHICALLY_VERIFIED")
            print("PASS_B09_GOVERNED_SHA_INTEGRITY_NOT_AUTHENTICITY_"+v,flush=True)

            def temp_changed(record,field="all"):
                update="raw_text="+quote(record[3])+",raw_sha256="+quote(record[4])+\
                       ",chain_sha256="+quote(record[6])
                return ("""BEGIN; ALTER TABLE """+TABLE+""" DISABLE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1;
                    UPDATE """+TABLE+" SET "+update+" WHERE execution_id="+quote(RUN)+
                    " AND seq=3; "+reader(RUN)+" ROLLBACK;")
            # Physical tamper requires bypassing owner-level immutable trigger.
            sql("UPDATE "+TABLE+" SET raw_text='{}' WHERE execution_id="+quote(RUN)+";",
                should_fail="B09_RECEIPT_IMMUTABLE")
            sql("DELETE FROM "+TABLE+" WHERE execution_id="+quote(RUN)+";",
                should_fail="B09_RECEIPT_IMMUTABLE")
            corrupt=sql("""BEGIN; ALTER TABLE """+TABLE+
                """ DISABLE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1;
                UPDATE """+TABLE+" SET raw_text=raw_text||' ' WHERE execution_id="+
                quote(RUN)+" AND seq=2; "+reader(RUN)+" ROLLBACK;")
            self.assertEqual(json.loads(corrupt.splitlines()[-1])["blocking_code"],
                             "B09_CHAIN_RAW_OR_PREV_HASH_INVALID")
            same={**raw[2][1],"judge_chat_ref":prod_chat}
            x=make_event(RUN,3,"JUDGE",same,events[1][6])
            self.assertEqual(json.loads(sql(temp_changed(x)).splitlines()[-1])["blocking_code"],
                             "B09_JUDGE_LOGICAL_SEPARATION_INVALID")
            same_instructions={**raw[2][1],"reviewer_prompt_sha256":producer_prompt}
            x=make_event(RUN,3,"JUDGE",same_instructions,events[1][6])
            self.assertEqual(json.loads(sql(temp_changed(x)).splitlines()[-1])["blocking_code"],
                             "B09_JUDGE_LOGICAL_SEPARATION_INVALID")
            sql(insert_event(events[0]),should_fail="duplicate key")
            foreign_payload={**shared,"execution_id":FOREIGN,"stage":"REQUEST"}
            sql(insert_event(make_event(FOREIGN,1,"REQUEST",foreign_payload,ZERO)),
                should_fail="lf_ig_native_chat_request_nonce_uq")
            sql("BEGIN; SET LOCAL ROLE service_role; "+insert_event(events[0])+" ROLLBACK;",
                should_fail="permission denied")
            # The canonical Step70 must remain fail closed until a SEPARATE
            # owner-approved contract amendment recognizes documentary risk.
            fake={"status":"PASS","validator_status":"PASS",
                "verdict":"PASS_INDEPENDENT_SEMANTIC",
                "producer_independence_proven":True,"model_call_count":1,
                "provider_receipt_ref":"native-chat://UNVERIFIED-TEST-REF",
                "candidate_sha256":good["candidate_sha256"],
                "scope_packet_sha256":good["scope_packet_sha256"],
                "result":{"unsupported_claims":[],"blocking_codes":[]}}
            step=json.loads(sql("BEGIN; SET LOCAL ROLE service_role; SELECT public."
                 "lf_profile_native_bridge_record_semantic_v1("+quote(RUN)+","+
                 jq(fake)+",'fixture://step70-test',"+quote(RUN)+")::text; COMMIT;").splitlines()[-1])
            self.assertEqual(step["blocking_code"],"LF_STEP70_NATIVE_RECEIPT_NOT_VERIFIED")
            self.assertEqual(sql("SELECT count(*) FROM public.lf_operation_execution_steps"
                " WHERE execution_id="+quote(RUN)+" AND step_id='semantic_judge';"),"0")
            self.assertEqual(sql("SELECT md5(pg_get_functiondef('public."
                "lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));"),
                step70_before)
            self.assertEqual(sql("SELECT md5(pg_get_functiondef('public."
                "lf_ig_g15_motor_temporary_v1(jsonb)'::regprocedure));"),g15_before)
            print("PASS_B09_NEGATIVES_TAMPER_REPLAY_FOREIGN_JUDGE_AND_STEP70_"+v,flush=True)

            sql(DOWN.read_text("utf-8"),should_fail="B09_ROLLBACK_NONEMPTY_NO_DATA_LOSS")
            self.assertEqual(sql("SELECT count(*) FROM "+TABLE+";"),"3")
            # Delete *fixtures only*, inside throwaway Docker. Never live RUNs.
            sql("ALTER TABLE "+TABLE+" DISABLE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1;"
                " DELETE FROM "+TABLE+" WHERE execution_id="+quote(RUN)+";"
                " ALTER TABLE "+TABLE+" ENABLE TRIGGER lf_ig_native_chat_receipt_no_mutation_v1;")
            sql(DOWN.read_text("utf-8"))
            self.assertEqual(sql("SELECT to_regprocedure("
                 "'public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL AND "
                 "to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL;"),"t")
            sql(DOWN.read_text("utf-8"),should_fail="B09_ROLLBACK_PREIMAGE_MISSING")
            self.assertEqual(sql("SELECT md5(pg_get_functiondef('public."
                "lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));"),
                step70_before)
            print("PASS_B09_GOVERNED_ROLLBACK_PRESERVES_UPSTREAM_"+v,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=90)

    def test_pg17_6(self):
        self.run_test("postgres:17.6","170006")

    def test_pg18_7(self):
        self.run_test("postgres:18","180007")

if __name__=="__main__":
    unittest.main()
