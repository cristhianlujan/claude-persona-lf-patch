"""Regression for the governed Git persistence exact-head readback."""
import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import patch

MODULE = pathlib.Path(__file__).with_name("lf_migration_git_persist.py")
spec = importlib.util.spec_from_file_location("lf_migration_git_persist", MODULE)
module = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = module
spec.loader.exec_module(module)

class GitPersistReadbackTest(unittest.TestCase):
    def test_transient_missing_then_exact_success(self):
        sha = "a" * 40
        readings = [
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 0, "b"*40 + "\trefs/heads/example\n", ""),
            subprocess.CompletedProcess([], 0, sha + "\trefs/heads/example\n", ""),
        ]
        with patch.object(module, "_run", side_effect=readings) as run, patch.object(module.time, "sleep") as sleep:
            module.require_remote_exact_head("lf/migration-source-persist/example", sha)
            self.assertEqual(run.call_count, 3)
            self.assertEqual(sleep.call_count, 2)
            self.assertTrue(all(call.kwargs.get("check") is False for call in run.call_args_list))

    def test_wrong_sha_never_succeeds(self):
        with patch.object(module, "_run", return_value=subprocess.CompletedProcess([], 0, "b"*40+"\trefs/heads/example\n", "")) as run, patch.object(module.time, "sleep") as sleep:
            with self.assertRaisesRegex(ValueError, "MIGRATION_GIT_PERSIST_REMOTE_READBACK_MISMATCH"):
                module.require_remote_exact_head("lf/migration-source-persist/example", "a"*40)
            self.assertEqual(run.call_count, 8)
            self.assertEqual(sleep.call_count, 7)

    def test_remote_error_never_succeeds(self):
        with patch.object(module, "_run", return_value=subprocess.CompletedProcess([], 128, "", "auth failure")) as run, patch.object(module.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "MIGRATION_GIT_PERSIST_REMOTE_READBACK_MISMATCH"):
                module.require_remote_exact_head("lf/migration-source-persist/example", "a"*40)
            self.assertEqual(run.call_count, 8)

if __name__ == "__main__":
    unittest.main()
