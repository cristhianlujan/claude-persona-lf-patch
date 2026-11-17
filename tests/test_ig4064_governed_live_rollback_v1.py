"""Static-only safety tests for IG4064 manual DB rollback workflow.

NOT a functional PASS; only PostgreSQL on the real governed environment can
prove the 135/135 recall, six source references, and 1,833-row regression.
"""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "sandbox/lf_contract_gate_test/input_governance/ig4064_governed_live_rollback_v1.py"
TEMPLATE = ROOT / "sandbox/lf_contract_gate_test/input_governance/ig4064_live_rollback_template_v1.sql"
WORKFLOW = ROOT / ".github/workflows/lf-ig-4064-live-rollback.yml"
REGISTRY = ROOT / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"

class GovernedRollbackContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text(encoding="utf-8")
        cls.sql = TEMPLATE.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_workflow_manual_only(self):
        self.assertIn("  workflow_dispatch:", self.workflow)
        self.assertNotIn("\n  pull_request:", self.workflow)
        self.assertNotIn("\n  push:", self.workflow)
        self.assertNotIn("\n  pull_request_target:", self.workflow)
        self.assertIn("environment: lf-merge-train", self.workflow)
        self.assertIn("github.ref == 'refs/heads/main'", self.workflow)

    def test_untrusted_sql_is_pinned_data(self):
        self.assertIn("6d9f33fe300432270fdf078a35d1ae56cc1c8fab", self.script)
        self.assertIn("370bfb1682bac0ca8e30f9cef179f7939d5a659f", self.script)
        self.assertIn("3df03ef574f2cd6e653ab7c38194c8bc04f6851d", self.script)
        self.assertIn("persist-credentials: false", self.workflow)
        self.assertIn("GITHUB_REPOSITORY", self.script)
        self.assertIn("PR4064_LIVE_HEAD_DRIFT", self.script)

    def test_single_transaction_and_no_commit(self):
        self.assertEqual(self.sql.splitlines().count("BEGIN;"), 1)
        self.assertEqual(self.sql.splitlines().count("ROLLBACK;"), 1)
        self.assertNotIn("\nCOMMIT;", self.sql)
        self.assertIn("SET LOCAL lock_timeout", self.sql)
        self.assertIn("IG4064_POST_ROLLBACK_PASS", self.sql)
        self.assertIn("COMMIT_FORBIDDEN", self.script)

    def test_real_coverage_assertions(self):
        for s in ("assessments=1974", "target_n<>141", "target_app<>130", "target_na<>11",
                  "other_screens<>39", "other_n<>1833", "other_app<>1824",
                  "other_na<>9", "hits<>45", "nas<>2", "refs<>2",
                  "losses<>0", "IG4064_NA_SOURCE_REFS_REAL="):
            self.assertIn(s, self.sql)

    def test_evidence_and_fail_closed(self):
        self.assertIn("actions/upload-artifact@v4", self.workflow)
        self.assertIn(".lf_ci/ig4064/report.json", self.workflow)
        self.assertIn("IG4064_POST_ROLLBACK_PASS", self.script)
        self.assertIn("report[\"status\"] = \"PASS\"", self.script)
        self.assertIn("readback", self.script)
        self.assertNotIn("GRANT EXECUTE", self.sql)
        self.assertNotIn("INSERT INTO lf_ops.reglas", self.sql)

    def test_registry_allows_only_exact_workflow(self):
        import json
        x = json.loads(REGISTRY.read_text(encoding="utf-8"))
        self.assertIn(".github/workflows/lf-ig-4064-live-rollback.yml",
                      x["path_admission"]["github_exact"])
        self.assertEqual(x["path_admission"]["default_github"], "DENY")

if __name__ == "__main__":
    unittest.main()
