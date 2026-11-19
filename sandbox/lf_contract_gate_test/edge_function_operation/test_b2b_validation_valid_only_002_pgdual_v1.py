"""PG17.6/PG18.7 live PostgreSQL validation for candidate VALID_ONLY ...002.
This checks the existing server-side constraints and rollback in disposable DBs.
It does NOT assert end-to-end upload, semantic judge, or production readiness.
The real ...002/..001 JSONB equivalence is independently checked by PR's PG17 SQL.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path
from test_b2b_validonly_storage_current_pg_gaps_v1 import DDL
from test_b2b_carga002_behavior_pgdual_v1 import EXT_DDL, TXN

ROOT = Path(__file__).resolve().parents[3]
MIGS = list((ROOT / "supabase/migrations").glob("*_lf_b2b_carga002_hardening_v1.sql"))
TARGET = "B2B-RULE-VALIDATION-VALID-ONLY-002"
SOURCE = "B2B-RULE-VALIDATION-VALID-ONLY-001"

class B2BValidOnly002PGDual(unittest.TestCase):
    def test_source_bound_valid_only_server_contract_pg17_pg18(self):
        self.assertEqual(len(MIGS), 1, "EXACT_HARDENING_MIGRATION_REQUIRED")
        self.assertIsNotNone(shutil.which("docker"), "REAL_DOCKER_REQUIRED")
        self.assertTrue(TARGET.endswith("002") and SOURCE.endswith("001"))
        migration = MIGS[0].read_text(encoding="utf-8")
        self.assertIn("cargas_lotes_valid_only_processed_chk", migration)
        self.assertIn("trg_cargas_lotes_block_unsafe_processing_v1", migration)
        for pg in ("17.6", "18.7"):
            with self.subTest(postgres=pg, rule=TARGET):
                name = "lf-b2b-valid002-" + uuid.uuid4().hex[:8]
                started = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", name,
                     "-e", "POSTGRES_PASSWORD=fixture-only", "postgres:" + pg],
                    capture_output=True, text=True, timeout=180)
                self.assertEqual(started.returncode, 0, started.stderr[-2000:])
                try:
                    for _ in range(90):
                        ready = subprocess.run(
                            ["docker", "exec", name, "pg_isready", "-U", "postgres"],
                            capture_output=True, text=True, timeout=15)
                        if ready.returncode == 0:
                            logs = subprocess.run(["docker", "logs", name],
                                                  capture_output=True, text=True, timeout=15)
                            if "PostgreSQL init process complete; ready to start up." in (logs.stdout + logs.stderr) or "database system is ready to accept connections" in (logs.stdout + logs.stderr):
                                break
                        time.sleep(0.5)
                    self.assertEqual(ready.returncode, 0, "POSTGRES_NOT_READY")

                    def run_sql(s):
                        # A container can report readiness before the socket is
                        # consistently accepting connections under shared CI load.
                        # Retry transport only; SQL assertion/constraint errors
                        # remain hard failures without retry or false PASS.
                        p = None
                        for transport_attempt in range(12):
                            p = subprocess.run(
                                ["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
                                 "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
                                input=s, capture_output=True, text=True, timeout=180)
                            if p.returncode == 0:
                                return p.stdout, p.stderr
                            transient = (
                                p.returncode == 2 and
                                ("No such file or directory" in p.stderr or
                                 "Connection refused" in p.stderr or
                                 "the database system is starting up" in p.stderr)
                            )
                            if not transient:
                                break
                            time.sleep(1)
                        self.assertEqual(p.returncode, 0, p.stderr[-5000:] + p.stdout[-2200:])
                        return p.stdout, p.stderr

                    run_sql(DDL + "\n" + EXT_DDL)
                    run_sql(migration)
                    run_sql("""CREATE TABLE lf_ops.rule_contract_scope (
                        codigo text PRIMARY KEY, scope text NOT NULL, source_code text NOT NULL);
                        INSERT INTO lf_ops.rule_contract_scope VALUES
                        ('""" + TARGET + """','PANTALLA','""" + SOURCE + """');""")
                    out, err = run_sql(TXN)
                    good = (
                        "POSITIVE_CLEAN_XLSX_SHA=1",
                        "INVALID_LOADS_REMAIN=0",
                        "INVALID_FILES_REMAIN=0",
                        "IDEMP_TWO_REQUESTS_ONE_ROW=1",
                        "HARDENING_CHECKS=4",
                        "HARDENING_TRIGGER=1",
                        "VALIDATION-CONTRACT=PASS",
                        "STORAGE-CONTRACT=PASS",
                        "ROLLBACK_NO_LOAD_ROWS=0",
                        "ROLLBACK_NO_FILE_ROWS=0",
                    )
                    rejected = (
                        "BLOCK_VALID_ONLY_PROCESSED_GT_VALID",
                        "BLOCK_COUNTS_SUM_GT_TOTAL",
                        "BLOCK_EXE_MIME_SPOOF",
                        "BLOCK_BAD_CHECKSUM",
                        "BLOCK_ZERO_SIZE",
                        "BLOCK_PROCESSING_FILE_NOT_CLEAN",
                    )
                    for marker in good:
                        self.assertIn(marker, out, marker + ": " + out[-1500:])
                    for marker in rejected:
                        self.assertIn(marker, err, marker + ": " + err[-1500:])
                    scoped, _ = run_sql(
                        "SELECT count(*) FROM lf_ops.rule_contract_scope WHERE codigo='"
                        + TARGET + "' AND scope='PANTALLA' AND source_code='" + SOURCE + "';")
                    self.assertIn("1", scoped.strip())
                    print("PASS_PG" + pg + "_VALID_ONLY_002_SOURCE_BOUND_SERVER_BEHAVIOR_AND_ROLLBACK", flush=True)
                finally:
                    subprocess.run(["docker", "rm", "-f", name],
                                   capture_output=True, timeout=30)

if __name__ == "__main__":
    unittest.main()
