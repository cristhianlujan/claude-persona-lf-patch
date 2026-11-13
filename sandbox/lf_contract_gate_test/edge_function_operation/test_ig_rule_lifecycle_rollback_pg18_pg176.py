#!/usr/bin/env python3
"""PR #3803 transactional reverse tests in isolated Docker PG18 and PG17.6.
No Supabase keys, no live mutations, no historical RUN changes.
"""
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
            self.assertEqual(len(before_md5.split(",")), 6)
            psql(FORWARD.read_text(encoding="utf-8"))
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

