"""Exercise real shallow Git transport and fail-closed commit recovery locally."""
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
spec = importlib.util.spec_from_file_location("audit_ci_baseline_transport",
    ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/test_deep_implementation_audit_skill_v1.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


def git(repo, *args, check=True):
    return subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, check=check)


class ShallowCheckoutProvenance(unittest.TestCase):
    def test_exact_baseline_fetch_preserves_source_checks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); origin = root / "origin"; origin.mkdir()
            git(origin, "init", "--initial-branch=main")
            git(origin, "config", "user.name", "Codex fixture")
            git(origin, "config", "user.email", "codex@openai.com")
            (origin / "consumer.py").write_text("def consume(row):\n    return row['required']\n")
            git(origin, "add", "consumer.py"); git(origin, "commit", "-m", "fixture baseline")
            baseline = git(origin, "rev-parse", "HEAD").stdout.strip()
            (origin / "candidate.txt").write_text("candidate fixture\n")
            git(origin, "add", "candidate.txt"); git(origin, "commit", "-m", "fixture candidate")
            shallow = root / "shallow"
            subprocess.run(["git", "clone", "--depth=1", "--no-local", origin.as_uri(), str(shallow)],
                           text=True, capture_output=True, check=True)
            self.assertEqual(git(shallow, "rev-parse", "--is-shallow-repository").stdout.strip(), "true")
            self.assertNotEqual(git(shallow, "cat-file", "-e", baseline + "^{commit}", check=False).returncode, 0)
            source_before = (shallow / "consumer.py").read_bytes()
            observed = adapter.ensure_baseline_commit(shallow, baseline)
            self.assertTrue(observed["fetched"])
            committed = subprocess.check_output(["git", "show", baseline + ":consumer.py"], cwd=shallow)
            self.assertEqual(committed, source_before)
            self.assertEqual((shallow / "consumer.py").read_bytes(), source_before)
            self.assertFalse(adapter.ensure_baseline_commit(shallow, baseline)["fetched"])
            with self.assertRaisesRegex(RuntimeError, "AUDIT_BASELINE_FETCH_FAILED"):
                adapter.ensure_baseline_commit(shallow, "f" * 40)

    def test_invalid_commit_is_rejected_before_transport(self):
        for invalid in (None, "main", "--all", "a" * 39, "z" * 40):
            with self.subTest(commit=invalid), self.assertRaisesRegex(ValueError, "AUDIT_BASELINE_COMMIT_INVALID"):
                adapter.ensure_baseline_commit(ROOT, invalid)


if __name__ == "__main__":
    unittest.main()
