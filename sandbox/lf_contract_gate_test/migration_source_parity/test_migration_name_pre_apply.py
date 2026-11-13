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

    def test_exact_m100_source_is_classified_before_train_apply(self) -> None:
        result = self.run_checker("ig_m100_sandbox_technical_vs_operational_authority_v1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("classification=MANAGED", result.stdout)

    def test_unreviewed_m100_names_still_fail_closed(self) -> None:
        result = self.run_checker("ig_m100_unreviewed_future_migration_v9")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY", result.stderr)

    def test_unknown_f0_name_fails_closed(self) -> None:
        result = self.run_checker("f0_unreviewed_name_v1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY", result.stderr)

    def test_pr3807_deployed_sql_not_reintroduced(self) -> None:
        # Merge Train consumed this exact deployed SQL; its rollback remains.
        delta = ROOT / "supabase/migrations/20261113060000_lf_router_scope_receipt_consumer_v2.sql"
        rollback = ROOT / (
            "sandbox/lf_contract_gate_test/input_governance_lifecycle/"
            "rollback_lf_router_scope_receipt_consumer_v2.sql"
        )
        self.assertFalse(delta.exists(), "PR3807_DEPLOYED_DELTA_REINTRODUCED")
        self.assertTrue(rollback.is_file(), "PR3807_ROLLBACK_ARTIFACT_MISSING")

    def test_b07_lf_only_migration_isolated_from_other_projects(self) -> None:
        b07 = ROOT / "supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql"
        self.assertTrue(b07.is_file(), "B07_LF_OFFICIAL_CANDIDATE_MISSING")
        source = b07.read_text(encoding="utf-8")
        self.assertIn("CREATE TABLE lf_ops.reglas_versiones_b07", source)
        self.assertIn("CREATE TABLE public.lf_b07_project_gate_v1", source)
        self.assertIn("CREATE FUNCTION public.lf_b07_project_preflight_v1", source)
        self.assertIn("PERFORM public.lf_b07_append_after_finalize_v1(p_child);", source)
        self.assertNotIn("saly.", source.lower(), "B07_CROSS_PROJECT_OBJECT")
        self.assertNotIn("saly_", source.lower(), "B07_CROSS_PROJECT_WRITER")
        self.assertNotIn("lf_b07_append_version_candidate_v1", source,
                         "B07_NON_OFFICIAL_WRITER_NOT_REMOVED")
        self.assertNotIn("ADD COLUMN lifecycle_", source,
                         "B07_OWNER_REJECTED_LIFECYCLE_COLUMNS")
        self.assertEqual(source.count("\nBEGIN;\n"), 1)
        self.assertEqual(source.count("\nCOMMIT;"), 1)
        for legacy in (
            "b07_saly_official_writer_candidate_v1.sql",
            "b07_saly_14_rows_fixture.sql",
            "b07_parent_child_candidate_up.sql",
            "b07_parent_child_v2_finalizer_integration_candidate.sql",
            "b07_parent_child_candidate_down.sql",
        ):
            self.assertFalse((ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle" / legacy).exists(),
                             "B07_NON_LF_SOURCE_IN_PR:" + legacy)
        deployed = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
        self.assertTrue(deployed.is_file())
        self.assertNotIn("lf_b07_append_after_finalize_v1", deployed.read_text(encoding="utf-8"),
                         "B07_UNGOVERNED_MUTATION_OF_DEPLOYED_V2")

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
