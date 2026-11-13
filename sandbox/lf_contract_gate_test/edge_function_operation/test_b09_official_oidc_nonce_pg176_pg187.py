#!/usr/bin/env python3
"""B09 isolated PG17.6/18.7 actual SQL apply/negative/rollback.
Never contacts Supabase, issues a real GitHub OIDC JWT, or runs a real profile.
The Step70/G15 dependency is pinned to PR #3829's immutable commit.
"""
import json
import re
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
PRESTEP70 = BASE / "pg18_step70_bridge_live_preimage.sql"
SCOPE = ROOT / "supabase/migrations/20261113083527_lf_router_scope_receipt_consumer_v2.sql"
RECEIVER = ROOT / "supabase/migrations/20261113143831_lf_ig_native_chat_sha_receiver_v1.sql"
WRITER_PRE = BASE / "b09_canonical_recorder_live_preimage_20261113.sql"
UP = ROOT / "supabase/migrations/20261113235500_lf_b09_official_oidc_nonce_writer_v1.sql"
DOWN = BASE / "rollback_lf_b09_official_oidc_nonce_writer_v1.sql"
DEP_SHA = "3bb05b3b9cf477bf0743670e4422775c7fd2c3d6"
DEP_PATH = "supabase/migrations/20261113220000_lf_ig_native_chat_step70_g15_documental_v1.sql"
RUN = "EXEC-PROFILE-GATE2-B09OFFICIALNONCE0001"
BAD_RUN = "EXEC-PROFILE-GATE2-B09OFFICIALNONCE0002"
ZERO = "0" * 64


def q(value):
    return "'" + str(value).replace("'", "''") + "'"


def j(value):
    return q(json.dumps(value, ensure_ascii=False, sort_keys=True,
                        separators=(",", ":"))) + "::jsonb"


def dependency_source():
    if subprocess.run(["git", "cat-file", "-e", DEP_SHA + "^{commit}"],
                      cwd=ROOT, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode != 0:
        fetched = subprocess.run(["git", "fetch", "--no-tags", "--depth=1",
                                  "origin", DEP_SHA], cwd=ROOT,
                                 capture_output=True, text=True, timeout=120)
        if fetched.returncode:
            raise AssertionError("B09_PR3829_PINNED_DEPENDENCY_FETCH_BLOCKED " +
                                 fetched.stderr[-800:])
    result = subprocess.run(["git", "show", DEP_SHA + ":" + DEP_PATH], cwd=ROOT,
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError("B09_PR3829_PINNED_DEPENDENCY_NOT_FOUND")
    return result.stdout


class B09OfficialOIDCWriterPG(unittest.TestCase):
    def test_dual_pg(self):
        self.assertIsNotNone(shutil.which("docker"), "B09_PG_DOCKER_UNAVAILABLE")
        for p in (SLICE, UPSTREAM, PRESTEP70, SCOPE, RECEIVER, WRITER_PRE, UP, DOWN):
            self.assertTrue(p.is_file(), "B09_PG_SOURCE_MISSING " + str(p))
        step70 = dependency_source()
        self.assertIn("LF_STEP70_SHA_OFFICIAL_WRITER_BINDING_MISSING", step70)
        for image, version in (("postgres:17.6", "170006"),
                               ("postgres:18", "180007")):
            self.check_pg(image, version, step70)

    def check_pg(self, image, version, step70):
        name = "lf-b09-oidc-" + uuid.uuid4().hex[:12]
        started = subprocess.run(["docker", "run", "-d", "--rm", "--name", name,
                                   "-e", "POSTGRES_PASSWORD=postgres", image],
                                 capture_output=True, text=True, timeout=240)
        self.assertEqual(started.returncode, 0, "B09_PG_DOCKER_START " + started.stderr)
        try:
            def sql(script, expected_error=None, timeout=450):
                x = subprocess.run(["docker", "exec", "-i", name, "psql", "-X",
                                    "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1",
                                    "-U", "postgres", "-d", "postgres"],
                                   input=script, capture_output=True,
                                   text=True, timeout=timeout)
                if expected_error:
                    self.assertNotEqual(x.returncode, 0, "B09_PG_NEGATIVE_ACCEPTED")
                    self.assertIn(expected_error, x.stderr,
                                  "B09_PG_UNEXPECTED_ERROR " + x.stderr[-1800:])
                else:
                    self.assertEqual(x.returncode, 0, "B09_PG_SQL_ERROR " + x.stderr[-2500:])
                return x.stdout.strip()

            for _ in range(50):
                if subprocess.run(["docker", "exec", name, "pg_isready", "-U", "postgres"],
                                  capture_output=True, timeout=10).returncode == 0:
                    break
                time.sleep(1)
            else:
                self.fail("B09_PG_NOT_READY")
            self.assertEqual(sql("SHOW server_version_num;"), version)
            sql(SLICE.read_text("utf-8"))
            train = "EXEC-DB-TRAIN-PR3803-20261113030000-R43379990009"
            train_manifest = {"producer": "lf-migration-merge-train", "pr": 3803,
                "train_run_id": "43379990009", "head_sha": "e"*40,
                "router_authority_receipt": {
                    "schema_version": "LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                    "operation_code": "ACTUALIZACION_DB_LF",
                    "target_repo": "cristhianlujan/claude-persona-lf-patch",
                    "target_code": "20261113030000_lf_ig_rule_lifecycle_writer_v2",
                    "target_path": "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql",
                    "route_eligibility_only": True, "scope_attested": False}}
            sql("INSERT INTO public.lf_operation_execution (execution_id,operation_code,"
                "target_type,target_code,target_repo,target_path,status,request_sha256,"
                "manifest,idempotency_key,created_by_execution_id) VALUES (" + ",".join([
                    q(train), q("ACTUALIZACION_DB_LF"), q("MIGRATION"),
                    q("20261113030000_lf_ig_rule_lifecycle_writer_v2"),
                    q("cristhianlujan/claude-persona-lf-patch"),
                    q("supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"),
                    q("IN_PROGRESS"), q("f"*64), j(train_manifest),
                    q("train:20261113030000:"+"e"*40),
                    q("LF-MIGRATION-TRAIN-RUN-43379990009")]) + ");")
            for p in (UPSTREAM, PRESTEP70, SCOPE, WRITER_PRE, RECEIVER):
                sql(p.read_text("utf-8"))
            def md5():
                return sql("SELECT md5(pg_get_functiondef('public."
                    "lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure));")
            self.assertEqual(md5(), "7cf717887006e278356a716f3fd80182",
                             "B09_PG_CANONICAL_PREIMAGE_NOT_REPRODUCED")
            sql(step70)
            sql(UP.read_text("utf-8"))
            self.assertNotEqual(md5(), "7cf717887006e278356a716f3fd80182")
            for table in ("lf_ig_native_chat_receipt_v1", "lf_ig_native_chat_nonce_v1"):
                self.assertEqual(sql("SELECT has_table_privilege('service_role',"
                    + q("public."+table) + ",'INSERT');"), "f")
            def add_run(eid, readonly=True, no_write=True):
                manifest = {"executor_mode":"GPT_NATIVE","executor_provider":"OPENAI_CHATGPT_NATIVE",
                    "read_only":readonly,"no_write":no_write,"no_promotion":True}
                sql("INSERT INTO public.lf_operation_execution (execution_id,operation_code,"
                    "target_type,target_code,status,request_sha256,idempotency_key,manifest,"
                    "created_by_execution_id) VALUES (" + ",".join([
                        q(eid),q("EJECUCION_PERFIL_LF"),q("PERFIL"),
                        q("PERFIL-PRODUCT-DIRECTOR-LF"),q("IN_PROGRESS"),
                        q("a"*64),q("b09-nonce:"+eid),j(manifest),q(eid)]) + ");")
            add_run(RUN)
            add_run(BAD_RUN, readonly=False)
            oidc = {"method":"GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1",
                    "repository":"cristhianlujan/claude-persona-lf-patch",
                    "workflow_ref":"cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main",
                    "run_id":"43390000001","workflow_sha":"b"*40}
            seed = {"candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
                    "producer_prompt_sha256":"c"*64,"_verified_oidc":oidc}
            def rpc(eid, step, payload):
                return json.loads(sql("BEGIN; SET LOCAL request.jwt.claim.role='service_role'; "
                    "SELECT public.lf_record_profile_execution_step_v1(" +
                    q(eid)+","+q(step)+",'actions://oidc/43390000001/b09',"+
                    j(payload)+","+q(eid)+")::text; COMMIT;").splitlines()[-1])
            self.assertEqual(rpc(BAD_RUN,"b09_native_nonce_issue",seed)["blocking_code"],
                             "B09_NONCE_RUN_NOT_ELIGIBLE")
            issued=rpc(RUN,"b09_native_nonce_issue",seed)
            self.assertEqual(issued["status"],"B09_SERVER_NONCE_ISSUED")
            nonce=issued["nonce"]
            self.assertRegex(nonce,r"^[0-9a-f]{48}$")
            self.assertEqual(rpc(RUN,"b09_native_nonce_issue",seed)["blocking_code"],
                             "B09_NONCE_REPLAY_OR_ALREADY_ISSUED")
            shared={"execution_id":RUN,"nonce":nonce,
                    "candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
                    "producer_prompt_sha256":"c"*64}
            records=[
              {"stage":"REQUEST",**shared},
              {"stage":"EXECUTOR",**shared,"executor_chat_ref":"https://chatgpt.com/c/fixture-producer",
               "provider_receipt_ref":"native-chat://UNVERIFIED-FIXTURE"},
              {"stage":"JUDGE",**shared,"executor_chat_ref":"https://chatgpt.com/c/fixture-producer",
               "judge_chat_ref":"https://chatgpt.com/c/fixture-judge","review_mode":"SAME_LLM_SEPARATE_CHAT",
               "reviewer_prompt_sha256":"d"*64},
            ]
            wrong={**records[0],"nonce":"deadbeef"}
            self.assertEqual(rpc(RUN,"b09_native_receipt_append",{"seq":1,"kind":"REQUEST",
                "raw_text":json.dumps(wrong),"_verified_oidc":oidc})["blocking_code"],
                "B09_EVENT_NONCE_OR_SCOPE_NOT_BOUND")
            for i,record in enumerate(records,1):
                out=rpc(RUN,"b09_native_receipt_append",{"seq":i,
                    "kind":record["stage"],"raw_text":json.dumps(record),
                    "_verified_oidc":oidc})
                self.assertEqual(out["status"],"B09_NATIVE_EVENT_RECORDED_DOCUMENTAL_ONLY")
                self.assertEqual(out["seq"],i)
            self.assertEqual(rpc(RUN,"b09_native_receipt_append",{"seq":3,"kind":"JUDGE",
                "raw_text":json.dumps(records[2]),"_verified_oidc":oidc})["blocking_code"],
                "B09_EVENT_SEQUENCE_OR_REPLAY")
            self.assertEqual(sql("SELECT count(*) FROM public.lf_operation_execution_steps "
                "WHERE execution_id="+q(RUN)+";"), "0")
            receipt=json.loads(sql("SELECT public.lf_ig_native_chat_official_writer_binding_receipt_v1("
                +q(RUN)+")::text;"))
            self.assertEqual(receipt["status"],"OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND")
            self.assertIs(receipt["identity_verified"],False)
            self.assertIs(receipt["effect_authority"],False)
            self.assertEqual(json.loads(sql("SELECT public.lf_ig_g15_motor_temporary_v1("
                "'{}'::jsonb)::text;"))["status"],"NO_GO_MOTOR")
            sql(DOWN.read_text("utf-8"),
                expected_error="B09_NONCE_ROLLBACK_DURABLE_RECEIPTS_PRESENT")
            sql("TRUNCATE public.lf_ig_native_chat_receipt_v1; "
                "TRUNCATE public.lf_ig_native_chat_nonce_v1;")
            sql(DOWN.read_text("utf-8"))
            self.assertEqual(md5(), "7cf717887006e278356a716f3fd80182")
            self.assertEqual(sql("SELECT to_regclass('public.lf_ig_native_chat_nonce_v1') "
                "IS NULL;"),"t")
            print("PASS_B09_CANONICAL_NONCE_WRITER_UP_NEGATIVES_DOWN_PG"+version,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=90)


if __name__ == "__main__":
    unittest.main()
