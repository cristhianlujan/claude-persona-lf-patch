"""PG17.6 / PG18.7: candidate wizard textual correction under ROLLBACK.

Fixtures reproduce only the source fields used by the governed CAS; no Supabase,
production, promotion, or external application write is performed.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261115205500_lf_b2b_carga002_wizard_three_step_text_v1.sql"
ORIGINAL = (
    "B2B-CARGA-002 organiza la preparación de cartera en cuatro estados UI: "
    "tipo y forma de carga, preparar datos, validar y cartera preparada. "
    "El mapeo de columnas es condicional: se omite para formato LF y puede omitirse "
    "cuando existe un mapeo gobernado previamente para la empresa. "
    "Estos estados UI no son estados de dominio UPLOAD_BATCH; las mutaciones "
    "siguen gobernadas por lf_ops.estados_transiciones."
)
CONFIG = {
    "screen_code": "B2B-CARGA-002",
    "ui_state_count": 3,
    "ui_states": ["OFFER_TYPE_AND_TEMPLATE", "UPLOAD_AND_PREPARE_DATA", "VALIDATE"],
    "wizard_completion": {
        "fourth_ui_step": "DENY",
        "domain_state_after_completion": "B2B_LOAD_VALIDADO"
    }
}

def q(s):
    return "'" + s.replace("'", "''") + "'"

def psql(name, sql, expect_success=True):
    r = subprocess.run(
        ["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
         "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
        input=sql, capture_output=True, text=True, timeout=120
    )
    if expect_success and r.returncode:
        raise AssertionError("POSTGRES_SQL_FAILED: " + r.stderr[-4000:])
    if not expect_success and not r.returncode:
        raise AssertionError("NEGATIVE_PROBE_UNEXPECTEDLY_SUCCEEDED")
    return r.stdout.strip()

class GovernedWizardDescriptionPGDual(unittest.TestCase):
    def test_transactional_patch_and_fail_closed_guard_pg17_pg18(self):
        self.assertTrue(shutil.which("docker"), "DOCKER_REQUIRED")
        src = MIG.read_text(encoding="utf-8")
        self.assertIn("LF_B2B_WIZARD_DESCRIPTION_PREIMAGE_DRIFT", src)
        self.assertIn("LF_B2B_WIZARD_CONFIG_AUTHORITY_DRIFT", src)
        self.assertIn("LF_B2B_WIZARD_POST_READBACK_FAILED", src)
        self.assertTrue(src.rstrip().endswith("COMMIT;"))
        body = src.split("\nBEGIN;\n", 1)[1].rsplit("\nCOMMIT;", 1)[0]
        seed = (
            "CREATE SCHEMA lf_ops;"
            "CREATE TABLE lf_ops.reglas ("
            "codigo text PRIMARY KEY, estado text NOT NULL, descripcion text,"
            "valor_config jsonb NOT NULL, updated_at timestamptz);"
            "INSERT INTO lf_ops.reglas (codigo,estado,descripcion,valor_config)"
            " VALUES ('B2B-RULE-LOAD-WIZARD-001','CANDIDATO',"
            + q(ORIGINAL) + "," + q(json.dumps(CONFIG)) + "::jsonb);"
        )
        for pg in ("17.6", "18.7"):
            with self.subTest(postgres=pg):
                name = "lf-b2b-three-step-" + uuid.uuid4().hex[:9]
                launched = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", name,
                     "-e", "POSTGRES_PASSWORD=fixture-only", "postgres:" + pg],
                    capture_output=True, text=True, timeout=180
                )
                self.assertEqual(launched.returncode, 0, launched.stderr[-1000:])
                try:
                    for _ in range(90):
                        ready = subprocess.run(
                            ["docker", "exec", name, "pg_isready", "-U", "postgres"],
                            capture_output=True, text=True, timeout=10
                        )
                        if ready.returncode == 0:
                            logs = subprocess.run(
                                ["docker", "logs", name], capture_output=True,
                                text=True, timeout=10
                            )
                            if "PostgreSQL init process complete; ready for start up." in (
                                logs.stdout + logs.stderr
                            ):
                                break
                        time.sleep(0.6)
                    self.assertEqual(ready.returncode, 0, "POSTGRES_NOT_READY")
                    psql(name, seed)
                    self.assertEqual(
                        psql(name, "SELECT md5(descripcion) FROM lf_ops.reglas;"),
                        "289f5579f9570815fd3d7580f5743dee"
                    )

                    # Positive: first application and replay both valid, then ROLLBACK.
                    test_sql = (
                        "BEGIN;\n" + body + "\n" + body +
                        "\nDO $assert$ BEGIN "
                        "IF NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE "
                        "codigo='B2B-RULE-LOAD-WIZARD-001' AND estado='CANDIDATO' "
                        "AND descripcion LIKE '%tres pasos UI%' "
                        "AND descripcion NOT LIKE '%cuatro estados UI%' "
                        "AND valor_config->>'ui_state_count'='3' "
                        "AND valor_config#>>'{wizard_completion,fourth_ui_step}'='DENY') "
                        "THEN RAISE EXCEPTION 'WIZARD_THREE_STEPS_POSTCONDITION'; "
                        "END IF; END $assert$; ROLLBACK;"
                    )
                    psql(name, test_sql)

                    # All negative probes fail in fresh transactions, rollback on disconnect.
                    for mutate in (
                        "UPDATE lf_ops.reglas SET descripcion='source drift';",
                        "UPDATE lf_ops.reglas SET estado='VIGENTE';",
                        "UPDATE lf_ops.reglas SET valor_config="
                        "jsonb_set(valor_config,'{ui_state_count}','4'::jsonb);",
                        "UPDATE lf_ops.reglas SET valor_config="
                        "jsonb_set(valor_config,'{wizard_completion,fourth_ui_step}',"
                        "'\"ALLOW\"'::jsonb);"
                    ):
                        with self.subTest(postgres=pg, mutation=mutate[:45]):
                            psql(name, "BEGIN;" + mutate + "\n" + body, False)
                            self.assertEqual(
                                psql(name, "SELECT md5(descripcion) FROM lf_ops.reglas;"),
                                "289f5579f9570815fd3d7580f5743dee"
                            )
                finally:
                    subprocess.run(["docker", "rm", "-f", name],
                                   capture_output=True, text=True, timeout=30)

if __name__ == "__main__":
    unittest.main()
