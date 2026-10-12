from __future__ import annotations

import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PARITY = pathlib.Path(__file__).resolve().parent
CHECKER = PARITY / "lf_migration_name_classification_check.py"
WORKFLOW = ROOT / ".github/workflows/lf-migration-merge-train.yml"


class MigrationNamePreApplyTest(unittest.TestCase):
    def run_checker(self, name: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), f"supabase/migrations/20261012213000_{name}.sql"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_known_name_passes(self) -> None:
        result = self.run_checker("f0_train_credential_canary_noop_v1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("classification=MANAGED", result.stdout)

    def test_unknown_f0_name_fails_closed(self) -> None:
        result = self.run_checker("f0_unreviewed_name_v1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY", result.stderr)

    def test_unclassified_name_is_gated_before_any_apply_step(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        gate = text.index("- name: Classify migration name before any write")
        persist = text.index("- name: Persist exact source and require Saga READY_TO_APPLY")
        apply = text.index("- name: Apply exact version and ledger readback")
        self.assertLess(gate, persist)
        self.assertLess(gate, apply)
        self.assertIn("FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY", text[gate:persist])


if __name__ == "__main__":
    unittest.main()
