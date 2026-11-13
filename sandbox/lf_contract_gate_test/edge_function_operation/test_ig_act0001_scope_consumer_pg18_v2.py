#!/usr/bin/env python3
"""PR #3807 PG18 execution test for ACT-0001 scope receipt consumption.
Real PostgreSQL DDL/DML in throwaway Docker; no live Supabase or provider.
The upstream PR #3803 live-object slice and migration are applied first.
"""
import json
import unittest
from pathlib import Path

from test_ig_rule_lifecycle_pg18 import PG18RealSQL, jq, quote, fail_assert

ROOT = Path(__file__).resolve().parents[3]
DELTA = ROOT / "supabase/migrations/20261113060000_lf_router_scope_receipt_consumer_v2.sql"
STEP70_BASELINE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_step70_bridge_live_preimage.sql"

ROLLBACK = ROOT / (
    "sandbox/lf_contract_gate_test/input_governance_lifecycle/"
    "rollback_lf_router_scope_receipt_consumer_v2.sql"
)

class ACT0001ScopeConsumerPG18(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fail_assert(DELTA.is_file() and ROLLBACK.is_file(),
                    "PR3807_DELTA_OR_ROLLBACK_MISSING")
        PG18RealSQL.setUpClass()
        cls.sql = PG18RealSQL.sql
        fail_assert(STEP70_BASELINE.is_file(),"PG18_STEP70_LIVE_SOURCE_FIXTURE_MISSING")
        cls.sql(STEP70_BASELINE.read_text("utf-8"), timeout=120)
        cls.sql(DELTA.read_text("utf-8"), timeout=120)
        fail_assert(cls.sql(
            "SELECT to_regprocedure("
            "'public.lf_router_scope_receipt_consume_v2(text,text)') IS NOT NULL;"
        ) == "t", "PR3807_DELTA_NOT_APPLIED")
        print("PASS_PR3807_PG18_EXACT_SINGLE_MIGRATION_APPLIED", flush=True)
        fail_assert(cls.sql("SELECT position('lf_router_scope_receipt_consume_v2' in "
          "pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))>0;")=="t",
                    "CANONICAL_ACT0001_SCOPE_ISSUER_NOT_HOOKED")
        fail_assert(cls.sql("SELECT position('LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING' in "
          "pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))>0;")=="t",
                    "CANONICAL_STEP70_NOT_FAIL_CLOSED")
        print("PASS_PR3807_PG18_CANONICAL_ACT0001_AND_STEP70_SOURCE_HOOKS", flush=True)


    @classmethod
    def tearDownClass(cls):
        PG18RealSQL.tearDownClass()

    def test_pg18_receipt_consume_negatives_and_inverse(self):
        run = "EXEC-DB-TRAIN-PR3807-SCOPE-ISOLATED"
        code = "20261113030000_lf_ig_rule_lifecycle_writer_v2"
        path = "supabase/migrations/" + code + ".sql"
        repo = "cristhianlujan/claude-persona-lf-patch"
        origin = {
            "schema_version": "LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
            "router": "ACT-0001",
            "operation_code": "ACTUALIZACION_DB_LF",
            "action_code": "UPDATE",
            "target_repo": repo, "target_path": path, "target_code": code,
            "scope_attested": False, "route_eligibility_only": True,
        }
        manifest = {
            "producer": "lf-migration-merge-train",
            "head_sha": "c3435fcb24af6de64721ca5cb043b011a9dba029",
            "train_run_id": "43372192579", "pr": "3803",
            "router_authority_receipt": origin,
        }
        self.sql(f"""INSERT INTO public.lf_operation_execution(
          execution_id,operation_code,target_type,target_code,target_repo,
          target_path,status,request_sha256,manifest,idempotency_key,
          created_by_execution_id)
          VALUES({quote(run)},'ACTUALIZACION_DB_LF','MIGRATION',
          {quote(code)},{quote(repo)},{quote(path)},'IN_PROGRESS',
          {quote('f'*64)},{jq(manifest)},{quote('scope-followup:'+run)},
          {quote(run)});""")
        # The upstream issuer derives positive/negative roles from DB source,
        # not a chat and not from the caller-provided scope fields.
        issued=json.loads(self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_bind_v1({quote(run)})::text;
            COMMIT;""").splitlines()[-1])
        fail_assert(issued["status"]=="SCOPE_ATTESTED_ROUTE_ONLY",
                    "ACT0001_UPSTREAM_SCOPE_ISSUANCE_FAILED")
        verified=json.loads(self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name')::text; COMMIT;""").splitlines()[-1])
        fail_assert(verified["status"]=="SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY"
                    and verified["scope_attested"] is True
                    and verified["effect_authority"] is False
                    and verified["downstream_execution_allowed"] is False
                    and verified["receipt_sha256"]==issued["receipt_sha256"],
                    "ACT0001_CONSUMER_POSITIVE_READBACK_FAILED")
        print("PASS_PR3807_PG18_SCOPE_CONSUMER_POSITIVE_READBACK",flush=True)

        # Real ACL, wrong column, forged/changed context, tampered persisted
        # receipt, changed schema all fail closed *without changing the run*.
        self.sql(f"""BEGIN; SET LOCAL ROLE anon;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name'); ROLLBACK;""",
            expect_fail="permission denied")
        self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_email'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_BUSINESS_COLUMN_FORBIDDEN")
        self.sql(f"""BEGIN;
            UPDATE public.lf_operation_execution SET manifest=
              jsonb_set(manifest,'{{head_sha}}',
                '"0000000000000000000000000000000000000000"'::jsonb)
            WHERE execution_id={quote(run)};
            SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_RECEIPT_TAMPERED_OR_STALE")
        self.sql(f"""BEGIN;
            UPDATE public.lf_router_scope_receipt_v1 SET
              receipt_sha256={quote('a'*64)}
            WHERE execution_id={quote(run)};
            SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_RECEIPT_TAMPERED_OR_STALE")
        self.sql(f"""BEGIN;
            ALTER TABLE public.lf_activos ADD COLUMN pg18_scope_extra text;
            SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_SCHEMA_OR_WRITER_DRIFT")
        self.sql(f"""BEGIN;
            UPDATE public.lf_operation_execution SET status='COMPLETED'
            WHERE execution_id={quote(run)};
            SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              {quote(run)},'owner_name'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_TRAIN_NOT_CURRENT")
        self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
            SELECT public.lf_router_scope_receipt_consume_v2(
              'EXEC-DB-TRAIN-NOT-EXIST','owner_name'); ROLLBACK;""",
            expect_fail="LF_SCOPE_V2_TRAIN_NOT_CURRENT")
        fail_assert(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1"
                             " WHERE execution_id="+quote(run)+";")=="1",
                    "NEGATIVES_DID_NOT_PRESERVE_ONE_RECEIPT")
        fail_assert(self.sql("SELECT status FROM public.lf_operation_execution"
                             " WHERE execution_id="+quote(run)+";")=="IN_PROGRESS",
                    "NEGATIVES_CHANGED_RUN_STATUS")
        print("PASS_PR3807_PG18_7_NEGATIVES_ZERO_EFFECTS",flush=True)

        # Actual canonical SQL Step70 call for an effects-bearing Product Director.
        # Without the trusted provider+attester backend it MUST be blocked.
        profile="EXEC-PROFILE-GATE2-PR3807STEP70NOAUTH"
        manifest={"executor_mode":"GPT_NATIVE",
          "executor_provider":"OPENAI_CHATGPT_NATIVE",
          "read_only":False,"no_write":False,"no_promotion":False}
        self.sql(f"""INSERT INTO public.lf_operation_execution(
          execution_id,operation_code,target_type,target_code,status,request_sha256,
          idempotency_key,manifest,created_by_execution_id)
          VALUES({quote(profile)},'EJECUCION_PERFIL_LF','PERFIL',
          'PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',{quote('b'*64)},
          {quote('scope-step70-negative:'+profile)},{jq(manifest)},{quote(profile)});""")
        fake_judge={"status":"PASS","validator_status":"PASS",
          "verdict":"PASS_INDEPENDENT_SEMANTIC",
          "producer_independence_proven":True,"model_call_count":1,
          "provider_receipt_ref":"actions://unverified-provider-claim",
          "candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
          "result":{"unsupported_claims":[],"blocking_codes":[]}}
        deny=json.loads(self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
           SELECT public.lf_profile_native_bridge_record_semantic_v1(
             {quote(profile)},{jq(fake_judge)},
             'actions://unverified-provider-claim',{quote(profile)})::text;
           COMMIT;""").splitlines()[-1])
        fail_assert(deny.get("status")=="BLOCKED" and
          deny.get("blocking_code")=="LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING",
          "STEP70_UNVERIFIED_PROVIDER_WAS_ACCEPTED "+str(deny))
        fail_assert(self.sql("SELECT count(*) FROM public.lf_operation_execution_steps "+
           "WHERE execution_id="+quote(profile)+" AND step_id='semantic_judge';")=="0",
          "STEP70_NEGATIVE_INSERTED_STEP")
        print("PASS_PR3807_PG18_REAL_CANONICAL_STEP70_MISSING_PROVIDER_BLOCKED_ZERO_EFFECTS",flush=True)

        self.sql(ROLLBACK.read_text("utf-8"),timeout=120)
        fail_assert(self.sql("SELECT to_regprocedure("
            "'public.lf_router_scope_receipt_consume_v2(text,text)') IS NULL;")=="t",
            "ROLLBACK_LEFT_NEW_CONSUMER")
        fail_assert(self.sql("SELECT to_regprocedure("
            "'public.lf_router_scope_bind_v1(text)') IS NOT NULL;")=="t",
            "ROLLBACK_DROPPED_UPSTREAM_ISSUER")
        fail_assert(self.sql("SELECT count(*) FROM public.lf_router_scope_receipt_v1"
                             " WHERE execution_id="+quote(run)+";")=="1",
                    "ROLLBACK_DELETED_SOURCE_RECEIPT")
        fail_assert(self.sql("SELECT md5(pg_get_functiondef("
          "'public.lf_router_scope_bind_v1(text)'::regprocedure));")
           =="41d48c7b836188547dc3fee85f4444f9",
           "ROUTER_ISSUER_ORIGINAL_SOURCE_NOT_RESTORED")
        fail_assert(self.sql("SELECT md5(pg_get_functiondef("
          "'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));")
           =="db59290a1c4ca6d87661a6ec5038d3f6",
           "STEP70_ORIGINAL_BRIDGE_SOURCE_NOT_RESTORED")
        print("PASS_PR3807_PG18_INVERSE_AND_UPSTREAM_PRESERVED",flush=True)

if __name__ == "__main__":
    unittest.main()
