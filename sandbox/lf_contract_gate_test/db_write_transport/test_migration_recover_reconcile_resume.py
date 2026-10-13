#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(name: str):
    p = HERE / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


request = load("lf_migration_operation_request")
recover = load("lf_migration_recover_preflight")
exact = load("lf_migration_exact_apply")
reconcile = load("lf_migration_reconcile_git")


class MigrationOperationModesTest(unittest.TestCase):
    def test_recover_request_exact_identity(self) -> None:
        body = """LF_MIGRATION_MODE: RECOVER
LF_RECOVER_PATH: supabase/migrations/20261013001500_lf_profile_evolution_phase_boundary_v1.sql
LF_RECOVER_BLOB: e17a50b18e4a239639eaeb936fe70e9be23cb0ca
LF_RECOVER_ISSUE: 2349
"""
        got = request.parse(body)
        self.assertEqual(got["operation_mode"], "RECOVER")
        self.assertEqual(got["recover_issue"], "2349")

    def test_recover_request_rejects_bad_blob(self) -> None:
        with self.assertRaises(ValueError):
            request.parse("""LF_MIGRATION_MODE: RECOVER
LF_RECOVER_PATH: supabase/migrations/20261013001500_x.sql
LF_RECOVER_BLOB: nope
LF_RECOVER_ISSUE: 2349
""")

    def test_reconcile_and_resume_modes(self) -> None:
        self.assertEqual(request.parse("LF_MIGRATION_MODE: RECONCILE\n")["operation_mode"], "RECONCILE")
        self.assertEqual(request.parse("LF_MIGRATION_MODE: RESUME\n")["operation_mode"], "RESUME")

    def test_recover_transaction_wrapper_is_stripped_only_at_boundaries(self) -> None:
        sql = "-- header\nBEGIN;\nselect 1;\nCOMMIT;\n"
        self.assertEqual(recover.strip_outer_transaction(sql).strip(), "-- header\n\nselect 1;")
        self.assertEqual(exact._strip_outer_transaction(sql).strip(), "-- header\n\nselect 1;")

    def test_recover_fallback_keeps_original_sql_in_ledger_but_executes_one_outer_transaction(self) -> None:
        sql = "-- header\nBEGIN;\nselect 1;\nCOMMIT;\n"
        out = exact.build_fallback_sql(
            version="20261013001500",
            name="x",
            source_sql=sql,
            source_blob="a" * 40,
            recover_existing_main=True,
        )
        self.assertIn("if not true and v_max", out)
        self.assertIn("array[$lfmig", out)
        # One executable outer begin plus the original text preserved only in the ledger literal.
        self.assertGreaterEqual(out.lower().count("begin;"), 2)
        self.assertIn(sql, out)

    def test_reconcile_canonical_ignores_comments_only(self) -> None:
        a = "-- old name\nselect 1;\n"
        b = "-- ledger\nselect 1;\n"
        self.assertEqual(reconcile.canonical(a), reconcile.canonical(b))
        self.assertNotEqual(reconcile.canonical(a), reconcile.canonical("select 2;\n"))


if __name__ == "__main__":
    unittest.main()
