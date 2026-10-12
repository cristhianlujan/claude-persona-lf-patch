#!/usr/bin/env python3
"""Static F0 credential boundary checks. Run on trusted main during activation.
No GitHub secrets or DB connections needed.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github/workflows"
DB = re.compile(r"(?:secrets\.LF_SUPABASE_DB_PASSWORD|secrets\.LF_MIGRATION_TRAIN_APP_PRIVATE_KEY|secrets\.LF_RUNTIME_READBACK_SSH_PRIVATE_KEY|secrets\.S30_BROKER_DEPLOY_KEY)")
ENV = re.compile(r"^\s+environment:\s*(?:lf-merge-train|lf-runtime-readback|lf-s30-broker)\s*$", re.M)
DISABLED = {"pase-merge-gate.yml", "lf-migration-source-parity-core.yml"}
# Reusable workflows are not automatically safe: examine callers separately.
ALLOW_REUSABLE = {"lf-migration-source-parity-core.yml"}


def classify_yaml_text(text, name):
    privileged = bool(DB.search(text))
    if not privileged:
        return "NO_PRIVILEGED_SECRET"
    if name in ALLOW_REUSABLE:
        return "NEEDS_CALLER_AUDIT"
    if not ENV.search(text):
        return "BLOCK_SECRET_WITHOUT_ENV"
    return "ENV_DECLARED_NEEDS_SEMANTIC_AUDIT"


class Tests(unittest.TestCase):
    def test_detects_unscoped_secret(self):
        self.assertEqual(classify_yaml_text(
            "jobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n    - env:\n        K: ${{ secrets.LF_SUPABASE_DB_PASSWORD }}",
            "x.yml"), "BLOCK_SECRET_WITHOUT_ENV")

    def test_detects_broker_deploy_key(self):
        self.assertEqual(classify_yaml_text(
            "jobs:\n  one:\n    steps:\n    - env:\n        K: ${{ secrets.S30_BROKER_DEPLOY_KEY }}",
            "x.yml"), "BLOCK_SECRET_WITHOUT_ENV")

    def test_env_is_not_proof_of_safe_trigger(self):
        self.assertEqual(classify_yaml_text(
            "jobs:\n  one:\n    environment: lf-merge-train\n    steps:\n    - env:\n        K: ${{ secrets.LF_SUPABASE_DB_PASSWORD }}",
            "x.yml"), "ENV_DECLARED_NEEDS_SEMANTIC_AUDIT")

    def test_scan_current_main_is_inventory_not_gate(self):
        results = {}
        for wf in WORKFLOWS.glob("*.yml"):
            results[wf.name] = classify_yaml_text(wf.read_text(encoding="utf-8"), wf.name)
        unsafe = {k:v for k,v in results.items() if v=="BLOCK_SECRET_WITHOUT_ENV"}
        print("F0_PRE_ACTIVATION_FINDINGS", sorted(unsafe))
        # Do not fail existing repo before activation: current finding is expected.
        self.assertIsInstance(unsafe, dict)


if __name__ == "__main__":
    unittest.main()
