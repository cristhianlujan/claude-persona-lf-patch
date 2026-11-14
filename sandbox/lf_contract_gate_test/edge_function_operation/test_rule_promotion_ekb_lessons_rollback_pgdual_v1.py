"""LF EKB promotion lessons: migration exercised only inside PG17.6/18.7 ROLLBACK.
No credentials, Supabase connections or modifications of actual rules.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261114165500_lf_rule_promotion_readback_ekb_lessons_v1.sql"
CODES = [
    "LF-PROMO-166-HOLD-ELIGIBILITY-20261114-001",
    "LF-PROMO-42501-VERDICT-READ-20261114-001",
    "LF-PROMO-INDEPENDENT-JUDGE-OWNER-20261114-001",
    "LF-PROMO-R17-PG-FIXTURE-20261114-001"
]
SCHEMA = """
CREATE TABLE public.lf_error_knowledge(
 id uuid,codigo text,categoria text,titulo text,descripcion text,causa_raiz text,
 patron text,prevencion text,validacion text,severidad text,frecuencia int,
 primera_vez timestamptz,ultima_vez timestamptz,lote_origen text,pr text,
 estado text,evidencia text,created_at timestamptz,updated_at timestamptz,
 lifecycle_phase text,consumer_role text[],root_cause_family text,
 detectability text,source_context text,source_ref text);
"""

class PromotionEKBRollback(unittest.TestCase):
    def test_pg17_pg18(self):
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED")
        sql = MIG.read_text(encoding="utf-8")
        for code in CODES:
            self.assertIn(code, sql)
        self.assertNotIn("UPDATE lf_ops.reglas", sql)
        self.assertNotIn("INSERT INTO public.lf_rule_promotion_v1", sql)
        body = sql.split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]
        for version in ("17.6", "18.7"):
            with self.subTest(pg=version):
                container = "lf-ekb-promotion-" + uuid.uuid4().hex[:8]
                run = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", container,
                     "-e", "POSTGRES_PASSWORD=fixture", "postgres:" + version],
                    capture_output=True, text=True, timeout=180)
                self.assertEqual(run.returncode, 0, run.stderr)
                try:
                    for _ in range(80):
                        ready = subprocess.run(
                            ["docker", "exec", container, "pg_isready", "-U", "postgres"],
                            capture_output=True, timeout=8)
                        if ready.returncode == 0:
                            logs = subprocess.run(["docker", "logs", container],
                                                  capture_output=True, text=True, timeout=8)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout + logs.stderr):
                                break
                        time.sleep(.7)
                    self.assertEqual(ready.returncode, 0)
                    q = (SCHEMA + "\nBEGIN;\n" + body + """
SELECT 'INSERTED='||count(*) FROM public.lf_error_knowledge;
SELECT 'DISTINCT='||count(distinct codigo) FROM public.lf_error_knowledge;
ROLLBACK;
SELECT 'POST_ROLLBACK='||count(*) FROM public.lf_error_knowledge;
SELECT 'RULES_UNTOUCHED='||(to_regclass('lf_ops.reglas') IS NULL)::text;
""")
                    result = subprocess.run(
                        ["docker", "exec", "-i", container, "psql", "-X",
                         "-A", "-t", "-U", "postgres", "-d", "postgres",
                         "-v", "ON_ERROR_STOP=1"],
                        input=q, capture_output=True, text=True, timeout=120)
                    self.assertEqual(result.returncode, 0, result.stderr[-4000:])
                    for expected in ("INSERTED=4", "DISTINCT=4",
                                     "POST_ROLLBACK=0", "RULES_UNTOUCHED=true"):
                        self.assertIn(expected, result.stdout)
                    print("PASS_EKB_PROMOTION_PG_" + version + "_ROLLBACK_TRUE")
                finally:
                    subprocess.run(["docker", "rm", "-f", container],
                                   capture_output=True, timeout=30)
