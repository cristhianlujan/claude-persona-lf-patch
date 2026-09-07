#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

RUNNER_PATH = Path(__file__).with_name("lf_governed_canary_runner.py")
spec = importlib.util.spec_from_file_location("lf_governed_canary_runner", RUNNER_PATH)
assert spec and spec.loader
runner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runner
spec.loader.exec_module(runner)

ZERO_TOKEN = "ZERO_RESIDUE_PASS"


def py_step(step_id: str, code: str, token: str = "OK", timeout: int = 5):
    return {
        "id": step_id,
        "argv": [sys.executable, "-c", code],
        "timeout_seconds": timeout,
        "env_names": [],
        "expect": {"exit_codes": [0], "stdout_contains": [token]},
    }


def manifest(tmp: Path):
    return {
        "contract_version": runner.VERSION,
        "canary_id": "TEST:CANARY-001",
        "change_mode": "GENERIC_SANDBOX",
        "target": {"environment": "sandbox", "production": False, "merge_authorized": False, "automatic_promotion": False},
        "steps": {
            "preflight": [py_step("PREFLIGHT", "print('OK')")],
            "forward": [py_step("FORWARD", "print('OK')")],
            "tests": [py_step("TEST", "print('OK')")],
            "rollback": [py_step("ROLLBACK", "print('OK')")],
            "post_readback": [py_step("POST", f"print('{ZERO_TOKEN}')", ZERO_TOKEN)],
        },
        "evidence": {
            "output_path": str(tmp / "evidence.json"),
            "include_raw_output": False,
            "require_post_readback": True,
            "require_zero_residue": True,
            "zero_residue_token": ZERO_TOKEN,
        },
    }


def migration_manifest(tmp: Path):
    m = manifest(tmp)
    m["change_mode"] = "MIGRATION_EXACT_VERSION"
    m["exact_versions"] = {"forward": "20260907215800", "rollback": "20260907215900"}
    m["source_first"] = {
        "main_ref": "origin/main",
        "paths": [
            "supabase/migrations/20260907215800_forward.sql",
            "supabase/migrations/20260907215900_rollback.sql",
        ],
        "require_identical_git_blob": True,
        "fetch_main": True,
    }
    return m


class RunnerTests(unittest.TestCase):
    def test_success(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d))
            packet = runner.execute_manifest(m)
            self.assertEqual(packet["result"], "PASS")
            self.assertTrue(packet["rollback_attempted"])
            self.assertTrue(packet["post_readback_attempted"])
            self.assertTrue(Path(m["evidence"]["output_path"]).exists())

    def test_production_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d)); m["target"]["production"] = True
            with self.assertRaisesRegex(runner.ContractError, "PRODUCTION_MUST_BE_FALSE"):
                runner.validate_manifest(m)

    def test_missing_rollback_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d)); m["steps"]["rollback"] = []
            with self.assertRaisesRegex(runner.ContractError, "ROLLBACK_STEPS_INVALID"):
                runner.validate_manifest(m)

    def test_shell_interpreter_rejected_by_default(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d)); m["steps"]["tests"][0]["argv"] = ["bash", "-lc", "echo OK"]
            with self.assertRaisesRegex(runner.ContractError, "SHELL_INTERPRETER_FORBIDDEN"):
                runner.validate_manifest(m)

    def test_exact_version_collision_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d)); m["change_mode"] = "MIGRATION_EXACT_VERSION"; m["exact_versions"] = {"forward":"20260907023000","rollback":"20260907023000"}
            with self.assertRaisesRegex(runner.ContractError, "FORWARD_ROLLBACK_VERSION_COLLISION"):
                runner.validate_manifest(m)

    def test_exact_version_source_first_required(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d))
            m["change_mode"] = "MIGRATION_EXACT_VERSION"
            m["exact_versions"] = {"forward": "20260907215800", "rollback": "20260907215900"}
            with self.assertRaisesRegex(runner.ContractError, "SOURCE_FIRST_REQUIRED"):
                runner.validate_manifest(m)

    def test_exact_version_source_first_contract_passes(self):
        with tempfile.TemporaryDirectory() as d:
            m = migration_manifest(Path(d))
            self.assertIs(runner.validate_manifest(m), m)

    def test_exact_version_source_first_path_binding_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            m = migration_manifest(Path(d))
            m["source_first"]["paths"][0] = "supabase/migrations/20260907023000_wrong.sql"
            with self.assertRaisesRegex(runner.ContractError, "SOURCE_FIRST_FORWARD_PATH_VERSION_MISMATCH"):
                runner.validate_manifest(m)

    def test_source_first_failure_happens_before_any_phase(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            m = migration_manifest(root)
            error = runner.source_first.SourceFirstParityError("SOURCE_FIRST_MAIN_SOURCE_MISSING:forward")
            with mock.patch.object(runner.source_first, "verify_paths", side_effect=error):
                packet = runner.execute_manifest(m)
            self.assertEqual(packet["result"], "FAIL_SOURCE_FIRST_PARITY")
            self.assertFalse(packet["forward_started"])
            self.assertFalse(packet["rollback_attempted"])
            self.assertEqual(packet["steps"], [])
            self.assertTrue(Path(m["evidence"]["output_path"]).exists())

    def test_zero_residue_must_be_executable_not_declarative(self):
        with tempfile.TemporaryDirectory() as d:
            m = manifest(Path(d)); m["steps"]["post_readback"][0]["expect"]["stdout_contains"] = ["OK"]
            with self.assertRaisesRegex(runner.ContractError, "ZERO_RESIDUE_TOKEN_NOT_ASSERTED"):
                runner.validate_manifest(m)

    def test_rollback_and_post_run_after_test_failure(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); marker = root / "marker.txt"
            m = manifest(root)
            m["steps"]["tests"] = [{"id":"TEST_FAIL","argv":[sys.executable,"-c","import sys; print('BAD'); sys.exit(7)"],"timeout_seconds":5,"env_names":[],"expect":{"exit_codes":[0]}}]
            m["steps"]["rollback"] = [py_step("ROLLBACK", f"from pathlib import Path; Path(r'{marker}').write_text('R'); print('OK')")]
            m["steps"]["post_readback"] = [py_step("POST", f"from pathlib import Path; assert Path(r'{marker}').read_text()=='R'; print('{ZERO_TOKEN}')", ZERO_TOKEN)]
            packet = runner.execute_manifest(m)
            self.assertEqual(packet["result"], "FAIL_CANARY")
            self.assertEqual(marker.read_text(), "R")
            phases = [x["phase"] for x in packet["steps"]]
            self.assertIn("rollback", phases); self.assertIn("post_readback", phases)

    def test_secret_value_not_written_to_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); secret = "SENSITIVE_VALUE_123"
            os.environ["LF_TEST_SECRET"] = secret
            try:
                m = manifest(root)
                m["steps"]["tests"] = [{"id":"ENV_TEST","argv":[sys.executable,"-c","import os; assert os.environ['LF_TEST_SECRET']; print('OK')"],"timeout_seconds":5,"env_names":["LF_TEST_SECRET"],"expect":{"exit_codes":[0],"stdout_contains":["OK"]}}]
                packet = runner.execute_manifest(m)
                self.assertEqual(packet["result"], "PASS")
                text = Path(m["evidence"]["output_path"]).read_text()
                self.assertNotIn(secret, text)
            finally:
                os.environ.pop("LF_TEST_SECRET", None)

    def test_timeout_fails_but_rolls_back(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); marker = root / "rollback.txt"
            m = manifest(root)
            m["steps"]["tests"] = [{"id":"TIMEOUT","argv":[sys.executable,"-c","import time; time.sleep(2); print('OK')"],"timeout_seconds":1,"env_names":[],"expect":{"exit_codes":[0]}}]
            m["steps"]["rollback"] = [py_step("ROLLBACK", f"from pathlib import Path; Path(r'{marker}').write_text('done'); print('OK')")]
            packet = runner.execute_manifest(m)
            self.assertEqual(packet["result"], "FAIL_CANARY")
            self.assertEqual(marker.read_text(), "done")


if __name__ == "__main__":
    unittest.main(verbosity=2)
