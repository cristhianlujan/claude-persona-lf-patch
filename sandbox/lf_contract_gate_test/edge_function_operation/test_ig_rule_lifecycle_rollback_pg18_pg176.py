#!/usr/bin/env python3
"""PR #3803 transactional reverse tests in isolated Docker PG18 and PG17.6.
No Supabase keys, no live mutations, no historical RUN changes.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
FORWARD = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
REVERSE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_ig_rule_lifecycle_writer_v2.sql"


class PR3803Rollback(unittest.TestCase):
    def roundtrip(self, image, expected_version_prefix):
        self.assertTrue(shutil.which("docker"), "NOT_TESTED_NO_DOCKER")
        for source in (FIXTURE, FORWARD, REVERSE):
            self.assertTrue(source.is_file(), "NOT_TESTED_SOURCE_MISSING:" + str(source))
        name = "lf-ig-rollback-" + uuid.uuid4().hex[:12]
        start = subprocess.run(["docker", "run", "-d", "--rm", "--name", name,
                                "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=postgres",
                                image], capture_output=True, text=True, timeout=240)
        self.assertEqual(start.returncode, 0, "NOT_TESTED_IMAGE_ERROR:" + start.stderr)
        try:
            def psql(sql, timeout=450, should_fail=None):
                p = subprocess.run(["docker", "exec", "-i", name, "psql", "-X",
                                    "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres",
                                    "-A", "-t", "-q"], input=sql, text=True,
                                   capture_output=True, timeout=timeout)
                if should_fail:
                    self.assertNotEqual(p.returncode, 0, "UNEXPECTED_SQL_SUCCESS")
                    self.assertIn(should_fail, p.stderr[-4000:])
                else:
                    self.assertEqual(p.returncode, 0, "SQL_FAILED:" + p.stderr[-5000:])
                return p.stdout.strip()
            for _ in range(60):
                alive = subprocess.run(["docker", "exec", name, "pg_isready", "-U", "postgres"],
                                       capture_output=True, text=True, timeout=20)
                if alive.returncode == 0:
                    break
                time.sleep(1)
            else:
                self.fail("POSTGRES_READY_TIMEOUT")
            version = psql("SHOW server_version_num;").splitlines()[-1]
            self.assertTrue(version.startswith(expected_version_prefix),
                            f"EXPECTED_{expected_version_prefix}_GOT_{version}")
            if image == "postgres:17.6":
                self.assertEqual(version, "170006")
            psql(FIXTURE.read_text(encoding="utf-8"))
            # Genuine Train RUN source is simulated solely in disposable
            # PG18/17.6; the forward SQL must reserve a NEW governed bootstrap.
            runid="43379990002"
            code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            train="EXEC-DB-TRAIN-PR3803-20261113030000-R"+runid
            repo="cristhianlujan/claude-persona-lf-patch"
            target="supabase/migrations/"+code+".sql"
            manifest={"producer":"lf-migration-merge-train","pr":3803,
              "train_run_id":runid,"head_sha":"e"*40,
              "router_authority_receipt":{
                 "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                 "operation_code":"ACTUALIZACION_DB_LF","target_repo":repo,
                 "target_code":code,"target_path":target,
                 "route_eligibility_only":True,"scope_attested":False}}
            payload=json.dumps(manifest,separators=(",",":"),ensure_ascii=False).replace("'","''")
            psql("""INSERT INTO public.lf_operation_execution(
              execution_id,operation_code,target_type,target_code,target_repo,
              target_path,status,request_sha256,manifest,idempotency_key,
              created_by_execution_id)
              VALUES('%s','ACTUALIZACION_DB_LF','MIGRATION','%s','%s',
              '%s','IN_PROGRESS','%s','%s'::jsonb,'%s','%s');"""%(
              train,code,repo,target,"f"*64,payload,
              "train:20261113030000:"+"e"*40,"LF-MIGRATION-TRAIN-RUN-"+runid))

            source_sql = """SELECT jsonb_agg(jsonb_build_object(
                'skill',skill_code,'opener',opener_fn,'required',input_required,
                'description',description) ORDER BY skill_code)::text
                FROM public.lf_skill_catalog_v1 WHERE skill_code IN
                ('RULE_CREATE_APPLY','RULE_UPDATE_APPLY');"""
            frozen_sql = """SELECT string_agg(md5(pg_get_functiondef(oid)),',' ORDER BY proname)
                FROM pg_proc WHERE pronamespace='public'::regnamespace
                AND proname IN ('lf_regla_candidate_write_v1','lf_skill_invoke_v1',
                    'lf_skill_o_rule_update_v1','lf_rule_promotion_apply_v1',
                    'lf_rule_promotion_decide_v1','lf_record_operation_step_core_v1');"""
            before = psql(source_sql)
            before_md5 = psql(frozen_sql)
            ig_contract_sql = """SELECT contract_sha||'|'||allowed::text||'|'||blocked::text
               FROM public.lf_operation_contracts
               WHERE operation_code='EJECUCION_INPUT_GOVERNANCE_LF';"""
            original_contract=psql(ig_contract_sql)
            self.assertTrue(original_contract.startswith(
              '783103f2196c1e49d1460bee239d41b74235be97f3b114ab27366f7c436afbb9|'))
            self.assertEqual(len(before_md5.split(",")), 6)
            psql(FORWARD.read_text(encoding="utf-8"))
            self.assertNotEqual(psql(ig_contract_sql),original_contract)
            self.assertEqual(psql("SELECT count(*) FROM public.lf_ig_contract_preimage_v3;"), "1")
            self.assertEqual(psql("SELECT count(*) FROM public.lf_ig_project_owner_v2;"), "1")
            psql("""INSERT INTO public.lf_ig_project_owner_v2
                (project_code,owner_sub,owner_name,owner_profile_code,authority_receipt_sha256,
                status,source_execution_id) VALUES
                ('SALY','00000000-0000-4000-8000-000000000111','Cristhian Luján',
                'LF_OWNER_PG_TEST',repeat('a',64),'CANDIDATE','EXEC-ROLLBACK-NEGATIVE');""")
            psql(REVERSE.read_text(encoding="utf-8"), should_fail="IG_ROLLBACK_NONEMPTY_V2_TABLES")
            self.assertEqual(psql("SELECT count(*) FROM public.lf_ig_project_owner_v2;"), "2")
            psql("DELETE FROM public.lf_ig_project_owner_v2 WHERE project_code='SALY';")
            psql(REVERSE.read_text(encoding="utf-8"))
            # Rollback removes only the new registry row. Preserve the
            # freshly reserved bootstrap execution for immutable audit history.
            bootstrap="EXEC-BOOTSTRAP-PROMOCION-REGLA-LF-R"+runid
            self.assertEqual(psql("SELECT count(*) FROM public.lf_operation_execution WHERE execution_id='"+
              bootstrap+"' AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF' "+
              "AND created_by_execution_id='"+train+"';"),"1",
              "BOOTSTRAP_AUDIT_RUN_REMOVED_OR_TAMPERED")
            self.assertEqual(psql(ig_contract_sql), original_contract, "IG_OPERATION_CONTRACT_NOT_RESTORED")
            self.assertEqual(psql("SELECT to_regclass('public.lf_ig_contract_preimage_v3') IS NULL;"),"t")
            self.assertEqual(psql(source_sql), before, "CATALOG_PREIMAGE_MISMATCH")
            self.assertEqual(psql(frozen_sql), before_md5, "LEGACY_MD5_MISMATCH")
            self.assertEqual(psql("SELECT to_regclass('public.lf_ig_project_owner_v2') IS NULL;"), "t")
            self.assertEqual(psql("SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='PROMOCION_REGLA_LF';"), "0")
            for proc in ("lf_rule_promotion_decide_v1(text,text,text,text)",
                         "lf_skill_o_rule_update_v1(text,jsonb,text,text,text)"):
                self.assertEqual(psql("SELECT has_function_privilege('service_role',"
                                      "'public." + proc + "','EXECUTE');"), "t")
            psql(REVERSE.read_text(encoding="utf-8"), should_fail="IG_ROLLBACK_MISSING_V2_OBJECTS")
            print("PASS_PR3803_REVERSE_" + image.replace(":", "_") + " version=" + version, flush=True)
        finally:
            subprocess.run(["docker", "rm", "-f", name], capture_output=True,
                           text=True, timeout=90)

    def test_pg18(self):
        self.roundtrip("postgres:18", "18")

    def test_pg17_6(self):
        self.roundtrip("postgres:17.6", "170006")


if __name__ == "__main__":
    unittest.main()

