"""Exercise the existing Profile Runtime issue-resume tests on the PR exact checkout.

The existing LF Edge Operation R17 Tests workflow owns this directory and
already runs unittest discovery on changed PR paths. No new workflow/runner.
Only Python stdlib; no network calls, credentials, or production writes.
"""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/test_profile_resume_issue_request.py"


class ProfileNativeIGBlockedBridgeTest(unittest.TestCase):
    def test_exact_checkout_contains_ig_blocked_receipt_handler(self):
        script = (ROOT / "scripts/lf_profile_native_resume.py").read_text(encoding="utf-8")
        self.assertIn("def record_blocked_ig_receipt(", script)
        self.assertIn("if record_blocked_ig_receipt(code, result, execution_id,", script)
        self.assertIn('"status": "BLOCKED_NOT_COMPLETE"', script)


    def test_v06_manifest_uses_existing_bound_runner(self):
        script = (ROOT / "scripts/lf_profile_native_resume.py").read_text(encoding="utf-8")
        self.assertIn("def unwrap_profile_native_evidence(", script)
        self.assertIn("def attach_bound_evidence_manifest(", script)
        self.assertIn('packet["evidence_manifest_sha256"]', script)
        workflow = (ROOT / ".github/workflows/lf-edge-deploy-credential-readback.yml").read_text(encoding="utf-8")
        self.assertIn("profile-native-evidence-manifest.json", workflow)


def load_tests(loader, tests, pattern):
    if not TARGET.is_file():
        raise RuntimeError("PROFILE_NATIVE_TEST_SOURCE_MISSING_IN_EXACT_CHECKOUT")
    spec = importlib.util.spec_from_file_location(
        "lf_profile_native_issue_resume_candidate_tests", TARGET
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("PROFILE_NATIVE_TEST_LOADER_MISSING")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tests.addTests(loader.loadTestsFromModule(module))
    return tests
