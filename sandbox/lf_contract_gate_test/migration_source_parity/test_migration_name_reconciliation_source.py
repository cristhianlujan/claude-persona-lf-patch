from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PARITY = pathlib.Path(__file__).resolve().parent
CHECKER = PARITY / "lf_migration_name_classification_check.py"
TRAIN_WORKFLOW = ROOT / ".github/workflows/lf-migration-merge-train.yml"
PR_WORKFLOW = ROOT / ".github/workflows/lf-migration-name-classification.yml"

VERSION = "20261006142429"
NAME = "engineering_parallel_executor_v1"  # legacy, unclassified by name


def header(version: str, name: str, execution: str = "EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001") -> str:
    return (
        "-- LF_MIGRATION_RECONCILIATION_SOURCE_V1\n"
        "-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY\n"
        "-- owner_binding_required=true\n"
        "-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF\n"
        "-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER\n"
        "-- source_authority=supabase_migrations.schema_migrations\n"
        f"-- reconciliation_owner_execution_id={execution}\n"
        f"-- source_version={version}\n"
        f"-- source_name={name}\n"
        "select 1;\n"
    )


class ReconciliationSourceClassificationTest(unittest.TestCase):
    def run_checker(self, cwd: pathlib.Path, rel: str, *flags: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), *flags, rel],
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
        )

    def write(self, root: pathlib.Path, version: str, name: str, body: str) -> str:
        rel = f"supabase/migrations/{version}_{name}.sql"
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")
        return rel

    def test_valid_header_passes_only_with_pr_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rel = self.write(root, VERSION, NAME, header(VERSION, NAME))
            ok = self.run_checker(root, rel, "--allow-reconciliation-source")
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertIn("classification=RECONCILIATION_SOURCE", ok.stdout)
            strict = self.run_checker(root, rel)
            self.assertNotEqual(strict.returncode, 0)
            self.assertIn("FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY", strict.stderr)

    def test_header_bound_to_other_name_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rel = self.write(root, VERSION, NAME, header(VERSION, "some_other_name_v1"))
            result = self.run_checker(root, rel, "--allow-reconciliation-source")
            self.assertNotEqual(result.returncode, 0)

    def test_header_with_invalid_execution_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rel = self.write(root, VERSION, NAME, header(VERSION, NAME, execution="UNKNOWN"))
            result = self.run_checker(root, rel, "--allow-reconciliation-source")
            self.assertNotEqual(result.returncode, 0)

    def test_unclassified_new_file_without_header_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rel = self.write(root, "20261013180000", "brand_new_unreviewed_v1", "select 1;\n")
            result = self.run_checker(root, rel, "--allow-reconciliation-source")
            self.assertNotEqual(result.returncode, 0)

    def test_removed_source_passes_only_with_pr_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            rel = f"supabase/migrations/20261010280000_t_remed_function_comments_v1.sql"
            ok = self.run_checker(root, rel, "--allow-reconciliation-source")
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertIn("classification=REMOVED_SOURCE", ok.stdout)
            self.assertNotEqual(self.run_checker(root, rel).returncode, 0)

    def test_train_never_uses_reconciliation_flag(self) -> None:
        self.assertNotIn("--allow-reconciliation-source", TRAIN_WORKFLOW.read_text(encoding="utf-8"))

    def test_pr_workflow_uses_reconciliation_flag(self) -> None:
        self.assertIn("--allow-reconciliation-source", PR_WORKFLOW.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
