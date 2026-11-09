import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[3] / "scripts/lf_vigente_documentary_migration.py"
spec = importlib.util.spec_from_file_location("lf_vigente_doc_generator", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def packet():
    return {
        "schema_version": "LF_VIGENTE_DOCUMENTARY_MAINTENANCE_REQUEST_V1",
        "operation_code": "ACTUALIZACION_DB_LF",
        "train": {"pr_number": 3713, "migration_version": "20261109062000", "migration_name": "lf_auth016_documentary_reconcile_v1"},
        "target": {"rule_id": 435, "rule_code": "B2B-RULE-AUTH-016", "state": "VIGENTE", "column": "pendiente_detalle"},
        "before": {"row_md5": "a" * 32, "material_md5": "b" * 32, "field_text": "Antes: it's possible"},
        "after": {"field_text": "Después: referencia ID10, prueba pendiente, 'autorización'"},
        "authority": {"decision_ref": "github://cristhianlujan/claude-persona-lf-patch/issues/3711", "source_ref": "supabase://lf_ops.reglas/B2B-RULE-AUTH-016"},
    }


class GeneratorTest(unittest.TestCase):
    def test_positive_guards_sql_and_escaping(self):
        sql = m.generate(packet())
        self.assertIn("DO $maintenance$", sql)
        self.assertIn("s.status='PASS_CLEAN'", sql)
        self.assertIn("'EXEC-DB-TRAIN-PR3713-%'", sql)
        self.assertIn("e.manifest#>>'{router_authority_receipt,operation_code}'='ACTUALIZACION_DB_LF'", sql)
        self.assertIn("md5((to_jsonb(v_rule)-'pendiente_detalle'-'updated_at')::text)", sql)
        self.assertIn("BLOCK_VIGENTE_DOC_READBACK_FAILED", sql)
        self.assertEqual(sql.count("UPDATE lf_ops.reglas"), 1)
        self.assertNotIn("\nCOMMIT;", sql)
        self.assertEqual(sql.count("DO $maintenance$"), 1)
        self.assertEqual(sql.count("\nDO $"), 1)
        self.assertEqual(sql.count("\n  UPDATE lf_ops.reglas"), 1)
        self.assertNotIn("SET estado=", sql)
        self.assertIn("'autorización'", sql)

    def test_counterexamples_block(self):
        mutations = [
            (lambda p: p["target"].update(column="descripcion"), "BLOCK_NOT_DOCUMENTARY_ONLY"),
            (lambda p: p["target"].update(state="CANDIDATO"), "BLOCK_NOT_DOCUMENTARY_ONLY"),
            (lambda p: p["train"].update(pr_number=0), "BLOCK_TRAIN_PR_INVALID"),
            (lambda p: p["train"].update(migration_name="DROP TABLE"), "BLOCK_TRAIN_NAME_INVALID"),
            (lambda p: p["before"].update(row_md5="deadbeef"), "BLOCK_BEFORE_ROW_HASH"),
            (lambda p: p["after"].update(field_text=p["before"]["field_text"]), "BLOCK_NO_EFFECT_DOCUMENT"),
            (lambda p: p["after"].update(field_text="invalid\x00null"), "BLOCK_DOCUMENT_NUL"),
            (lambda p: p["authority"].update(source_ref="x\n-- unsafe"), "BLOCK_AUTHORITY_REFERENCE"),
        ]
        for mutate, code in mutations:
            p = packet()
            mutate(p)
            with self.subTest(code=code), self.assertRaisesRegex(m.CandidateError, code):
                m.generate(p)

    def test_cli_output_only_and_never_overwrite(self):
        import subprocess
        import sys
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "supabase/migrations").mkdir(parents=True)
            request = root / "request.json"
            request.write_text(json.dumps(packet(), ensure_ascii=False), encoding="utf-8")
            output = root / "supabase/migrations/20261109062000_lf_auth016_documentary_reconcile_v1.sql"
            cmd = [sys.executable, str(SCRIPT), "--packet", str(request), "--output", "supabase/migrations/20261109062000_lf_auth016_documentary_reconcile_v1.sql"]
            run = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout)["status"], "CANDIDATE_GENERATED_NOT_APPLIED")
            self.assertTrue(output.is_file())
            repeat = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
            self.assertEqual(repeat.returncode, 2)
            self.assertEqual(json.loads(repeat.stdout)["code"], "BLOCK_MIGRATION_OUTPUT_EXISTS")

    def test_dollar_quote_collision(self):
        value = "frase 'single' con ; COMMIT; y caracteres $lfdoc$"
        q = m.literal(value)
        self.assertEqual(q[0], '$')
        self.assertEqual(q.split('$', 2)[1], q.rsplit('$', 2)[1])
        self.assertIn(value, q)

    def test_material_guard_remains_constant(self):
        sql = m.generate(packet())
        self.assertEqual(sql.count("'" + "b" * 32 + "'"), 2)
        self.assertEqual(sql.count("'" + "a" * 32 + "'"), 2)

    def test_no_implicit_runtime_or_prod_authority(self):
        sql = m.generate(packet())
        self.assertIn("Generated candidate; only ACTUALIZACION_DB_LF", sql)
        self.assertIn("reversal requires a NEW guarded governed migration", sql)
        self.assertNotIn("GRANT EXECUTE", sql)
        self.assertNotIn("CREATE OR REPLACE FUNCTION", sql)


if __name__ == "__main__":
    unittest.main()
