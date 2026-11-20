#!/usr/bin/env python3
"""B09 CANDIDATE: real PG17.6/18.7 disposable Docker tests. No live DB.
A hash verifies bytes, NOT ChatGPT origin, judge model independence or writer authenticity.
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
DIR = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle"
UP = DIR / "b09_native_chat_sha_receiver_candidate_v1.sql"
DOWN = DIR / "rollback_b09_native_chat_sha_receiver_candidate_v1.sql"
TABLE = "public.lf_ig_native_chat_e2e_receipt_candidate_v1"
RUN = "EXEC-PROFILE-GATE2-B09NATIVEPGTEST0001"
GENESIS = "0" * 64

def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def qt(text):
    return "'" + str(text).replace("'", "''") + "'"

def event(run, index, kind, payload, previous):
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    raw_hash = sha(raw)
    writer_sha = sha("test-only-nonauthenticated-writer-receipt")
    link = sha("|".join(["LF_NATIVE_CHAT_EVENT_V1",run,str(index),kind,
                         raw_hash,previous,writer_sha]))
    return (run,index,kind,raw,raw_hash,previous,link,
            "fixture://WRITER_NOT_AUTHENTICATED",writer_sha)

def insert_sql(e):
    return ("INSERT INTO "+TABLE+" (execution_id,seq,kind,raw_text,raw_sha256,"
            "prev_sha256,chain_sha256,writer_receipt_ref,writer_receipt_sha256)"
            " VALUES ("+",".join(str(v) if i==1 else qt(v)
                                   for i,v in enumerate(e))+");")

class B09NativeChatShaCandidate(unittest.TestCase):
    def roundtrip(self, image, expected_version):
        self.assertIsNotNone(shutil.which("docker"), "NOT_TESTED_NO_DOCKER")
        for file in (UP, DOWN):
            self.assertTrue(file.is_file(), "CANDIDATE_SOURCE_MISSING:"+str(file))
        name = "lf-b09-native-" + uuid.uuid4().hex[:11]
        p = subprocess.run(["docker","run","-d","--rm","--name",name,
                            "-e","POSTGRES_PASSWORD=postgres",
                            "-e","POSTGRES_DB=postgres",image],
                           text=True,capture_output=True,timeout=240)
        self.assertEqual(p.returncode,0,"DOCKER_FAILED:"+p.stderr)
        try:
            def psql(sql, expected_failure=None):
                q=subprocess.run(["docker","exec","-i",name,"psql",
                    "-X","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres",
                    "-A","-t","-q"],input=sql,text=True,capture_output=True,timeout=180)
                if expected_failure:
                    self.assertNotEqual(q.returncode,0,"UNEXPECTED_SQL_SUCCESS "+sql[:130])
                    self.assertIn(expected_failure,q.stderr,
                                  "EXPECTED_NEGATIVE_MISSING:"+q.stderr[-1500:])
                else:
                    self.assertEqual(q.returncode,0,"PG_SQL_FAILED:"+q.stderr[-3000:])
                return q.stdout.strip()
            for _ in range(60):
                ready=subprocess.run(["docker","exec",name,"pg_isready",
                                      "-U","postgres"],capture_output=True,text=True,timeout=15)
                if ready.returncode==0: break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            version=psql("SHOW server_version_num;").splitlines()[-1]
            self.assertEqual(version,expected_version,"PG_EXACT_VERSION_DRIFT")
            psql("CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;"
                 "CREATE ROLE service_role NOLOGIN;")
            # Ensure the test-controlled baseline includes pgcrypto,
            # which the inverse intentionally preserves.
            psql("CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;")
            pre=psql("SELECT to_regclass('"+TABLE+"') IS NULL AND "
                     "to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL;")
            self.assertEqual(pre,"t")
            psql(UP.read_text("utf-8"))
            self.assertEqual(psql("SELECT has_function_privilege('service_role',"
              "'public.lf_ig_verified_native_provider_receipt_v1(text)','EXECUTE');"),"t")
            self.assertEqual(psql("SELECT has_function_privilege('anon',"
              "'public.lf_ig_verified_native_provider_receipt_v1(text)','EXECUTE');"),"f")
            self.assertEqual(psql("SELECT has_table_privilege('service_role',"
              "'"+TABLE+"','INSERT');"),"f")
            psql("BEGIN; SET LOCAL ROLE anon; SELECT public."
                 "lf_ig_verified_native_provider_receipt_v1("+qt(RUN)+"); ROLLBACK;",
                 expected_failure="permission denied")
            missing=json.loads(psql("SELECT public."
                 "lf_ig_verified_native_provider_receipt_v1("+qt(RUN)+")::text;").splitlines()[-1])
            self.assertEqual(missing["blocking_code"],"CHAIN_INCOMPLETE")

            shared={"execution_id":RUN, "nonce":"test-once-nonce-0001",
                    "candidate_sha256":sha("candidate-content"),
                    "scope_packet_sha256":sha("server-scoped-packet")}
            exref="https://chatgpt.com/c/example-producer-unverified"
            judgeref="https://chatgpt.com/c/example-reviewer-unverified"
            entries=[
                ("REQUEST",{**shared,"stage":"REQUEST"}),
                ("EXECUTOR",{**shared,"stage":"EXECUTOR",
                             "executor_chat_ref":exref,
                             "provider_receipt_ref":"native-chat://unverified/executor-001"}),
                ("JUDGE",{**shared,"stage":"JUDGE",
                          "executor_chat_ref":exref,"judge_chat_ref":judgeref,
                          "review_mode":"SAME_LLM_SEPARATE_CHAT",
                          "reviewer_prompt_sha256":sha("prompt-versioned-v1"),
                          "verdict":"PASS"})
            ]
            previous=GENESIS
            records=[]
            for n,(kind,payload) in enumerate(entries,1):
                e=event(RUN,n,kind,payload,previous)
                records.append(e)
                previous=e[6]
                psql(insert_sql(e))
            output=json.loads(psql("SELECT public.lf_ig_verified_native_provider_receipt_v1("
                                    +qt(RUN)+")::text;").splitlines()[-1])
            self.assertEqual(output["status"],"SHA_CHAIN_INTACT_NATIVE_PROVENANCE_UNATTESTED")
            self.assertEqual(output["chain_tip_sha256"],records[-1][6])
            self.assertTrue(output["integrity_verified"])
            for field in ("writer_identity_verified","vendor_model_provenance_verified",
                          "reviewer_independence_proven","effect_authority",
                          "downstream_execution_allowed"):
                self.assertFalse(output[field],field)
            self.assertNotEqual(output["status"],"CRYPTOGRAPHICALLY_VERIFIED")
            print("PASS_B09_SHA_CHAIN_INTEGRITY_ONLY_"+expected_version,flush=True)

            q="SELECT public.lf_ig_verified_native_provider_receipt_v1("+qt(RUN)+")::text;"
            tamper=psql("BEGIN; UPDATE "+TABLE+" SET raw_text=raw_text||' ' WHERE "
                         "execution_id="+qt(RUN)+" AND seq=2; "+q+" ROLLBACK;")
            self.assertEqual(json.loads(tamper.splitlines()[-1])["blocking_code"],
                             "CHAIN_RAW_OR_PREV_HASH_INVALID")
            link=psql("BEGIN; UPDATE "+TABLE+" SET chain_sha256=repeat('f',64)"
                      " WHERE execution_id="+qt(RUN)+" AND seq=3; "+q+" ROLLBACK;")
            self.assertEqual(json.loads(link.splitlines()[-1])["blocking_code"],
                             "CHAIN_LINK_HASH_INVALID")
            missing_step=psql("BEGIN; DELETE FROM "+TABLE+" WHERE execution_id="+
                              qt(RUN)+" AND seq=3; "+q+" ROLLBACK;")
            self.assertEqual(json.loads(missing_step.splitlines()[-1])["blocking_code"],
                             "CHAIN_INCOMPLETE")
            wrong_judge={**entries[-1][1],"judge_chat_ref":exref}
            altered=event(RUN,3,"JUDGE",wrong_judge,records[1][6])
            same_chat=psql("BEGIN; UPDATE "+TABLE+" SET raw_text="+qt(altered[3])+
                ",raw_sha256="+qt(altered[4])+",chain_sha256="+qt(altered[6])+
                " WHERE execution_id="+qt(RUN)+" AND seq=3; "+q+" ROLLBACK;")
            self.assertEqual(json.loads(same_chat.splitlines()[-1])["blocking_code"],
                             "JUDGE_LOGICAL_SEPARATION_INVALID")
            psql(insert_sql(records[0]),expected_failure="duplicate key")
            reused=event("EXEC-PROFILE-GATE2-B09OTHERPGTEST0002",1,"REQUEST",
                         {**shared,"execution_id":"EXEC-PROFILE-GATE2-B09OTHERPGTEST0002"},
                         GENESIS)
            psql(insert_sql(reused),expected_failure=
                 "lf_ig_native_chat_e2e_request_nonce_candidate_uq")
            psql("BEGIN; SET LOCAL ROLE service_role; "+insert_sql(reused)+" ROLLBACK;",
                 expected_failure="permission denied")
            print("PASS_B09_NEGATIVES_TAMPER_REPLAY_JUDGE_ACL_"+expected_version,flush=True)

            psql(DOWN.read_text("utf-8"),expected_failure="B09_CANDIDATE_ROLLBACK_NONEMPTY_DATA")
            self.assertEqual(psql("SELECT count(*) FROM "+TABLE+";"),"3")
            # This DELETE is test-fixture cleanup in disposable Docker only.
            psql("DELETE FROM "+TABLE+" WHERE execution_id="+qt(RUN)+";")
            psql(DOWN.read_text("utf-8"))
            after=psql("SELECT to_regclass('"+TABLE+"') IS NULL AND "
                "to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL;")
            self.assertEqual(pre,after,"ROLLBACK_CATALOG_DRIFT")
            psql(DOWN.read_text("utf-8"),expected_failure=
                 "B09_CANDIDATE_ROLLBACK_PREIMAGE_MISSING")
            print("PASS_B09_ROLLBACK_FAIL_CLOSED_AND_INVERSE_"+expected_version,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=90)

    def test_pg17_6(self):
        self.roundtrip("postgres:17.6","170006")

    def test_pg18_7(self):
        self.roundtrip("postgres:18","180007")

if __name__=="__main__":
    unittest.main()
