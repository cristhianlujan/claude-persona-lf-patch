#!/usr/bin/env python3
"""Output pair within existing harness; bounded local checks only, no ledger writes."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CORE = Path(__file__).with_name("pack_validation_harness_v1.py")
spec = importlib.util.spec_from_file_location("pack_harness_output_pair", CORE)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(root: Path, path: str, content: str) -> None:
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def run_git(root: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(root), *args],
                          capture_output=True, text=True, check=True, timeout=12)
    return done.stdout.strip()


class PairValidation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lf-pair-")
        self.addCleanup(self.temp.cleanup)
        self.parent = Path(self.temp.name)
        self.root = self.parent / "checkout"
        self.root.mkdir()
        paths = [
            "skills/profile_creator/validators/profile_output_shape_preflight_v1.py",
            "skills/profile_creator/validators/run_bound_profile_output_validator_v1.py",
        ]
        for path in paths:
            f = self.root / path
            f.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, f)
        schema = {
            "type": "object", "required": ["deliverable_created", "self_verdict"],
            "properties": {
                "deliverable_created": {"type": "object", "required": ["authority_status"],
                    "properties": {"authority_status": {"enum": ["SUPPORTED"]}}},
                "self_verdict": {"enum": ["PASS"]}
            }
        }
        write(self.root, "profiles/alpha/schemas/output.schema.json", json.dumps(schema))
        write(self.root, "profiles/alpha/validators/validate_alpha.py",
              "import json,sys\n"
              "o=json.load(sys.stdin)\n"
              "ok=o.get('allow') is not False\n"
              "print(json.dumps({'valid':ok,'errors':[] if ok else [{'code':'DISALLOWED'}]}))\n")
        write(self.root, "evidence/positive.json", json.dumps({
            "deliverable_created": {"authority_status": "SUPPORTED"}, "self_verdict": "PASS"
        }))
        write(self.root, "evidence/negative.json", json.dumps({
            "deliverable_created": {}, "self_verdict": "PASS"
        }))
        self._binding("positive", True)
        self._binding("negative", False)
        run_git(self.root, "init", "-q")
        run_git(self.root, "config", "user.email", "lf-tests@example.invalid")
        run_git(self.root, "config", "user.name", "LF tests")
        run_git(self.root, "add", ".")
        run_git(self.root, "commit", "-qm", "version pair proof inputs")
        self.head = run_git(self.root, "rev-parse", "HEAD")
        self.request = self.parent / "request.json"
        self._request(self.head)

    def _binding(self, label: str, expected: bool):
        refs = {
            "schema": "profiles/alpha/schemas/output.schema.json",
            "validator": "profiles/alpha/validators/validate_alpha.py",
            "raw_output": f"evidence/{label}.json",
        }
        p = {
            "schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1",
            "operation_code": "ACTUALIZACION_PERFIL_LF",
            "profile_slug": "alpha",
            "validator_transport": "STDIN_JSON",
            "expected_valid": expected,
        }
        for key, ref in refs.items():
            p[key + "_ref"] = ref
            p[key + "_sha256"] = sha(self.root / ref)
        write(self.root, f"evidence/{label}.binding.json", json.dumps(p))

    def _request(self, head: str, positive="evidence/positive.binding.json",
                 negative="evidence/negative.binding.json"):
        self.request.write_text(json.dumps({
            "schema": "LF_PROFILE_OUTPUT_PAIR_REQUEST_V1",
            "profile_slug": "alpha", "candidate_head_sha": head,
            "positive_binding_ref": positive,
            "negative_binding_ref": negative,
        }), encoding="utf-8")

    def test_positive_and_negative_shape_pair(self):
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertEqual(actual["status"], "LOCAL_PAIR_VALIDATED_UNATTESTED", actual)
        self.assertEqual(actual["positive"]["status"], "CANDIDATE_OUTPUT_PARITY_OBSERVED")
        self.assertEqual(actual["negative"]["status"], "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE")
        self.assertFalse(actual["provider_attested"])
        self.assertFalse(actual["provider_readback_verified"])
        self.assertFalse(actual["candidate_admitted"])
        self.assertEqual(actual["ledger_receipts_created"], 0)
        self.assertRegex(actual["result_sha256"], "^[0-9a-f]{64}$")

    def test_negative_validator_can_exit_zero(self):
        write(self.root, "evidence/negative.json", json.dumps({
            "deliverable_created": {"authority_status": "SUPPORTED"},
            "self_verdict": "PASS", "allow": False
        }))
        # Schema permits non-disallowed extra key by default; validator rejects.
        self._binding("negative", False)
        run_git(self.root, "add", ".")
        run_git(self.root, "commit", "-qm", "validator-only negative")
        self._request(run_git(self.root, "rev-parse", "HEAD"))
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertEqual(actual["status"], "LOCAL_PAIR_VALIDATED_UNATTESTED", actual)
        self.assertEqual(actual["negative"]["status"], "EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR")
        self.assertEqual(actual["negative"]["validator_exit_code"], 0)

    def test_rejects_tampered_output_after_commit(self):
        write(self.root, "evidence/positive.json", '{"changed":true}')
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertEqual(actual["status"], "BLOCKED")
        self.assertTrue(any(x.startswith("PAIR_GIT_SOURCE_MISMATCH:")
                            for x in actual["blocking_codes"]))

    def test_rejects_stale_head(self):
        self._request("a" * 40)
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertIn("PAIR_HEAD_STALE", actual["blocking_codes"])

    def test_rejects_negative_swapped_with_positive(self):
        self._request(self.head, negative="evidence/positive.binding.json")
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertIn("PAIR_EXPECTED_VALIDITY_INVALID:negative", actual["blocking_codes"])

    def test_rejects_untracked_output(self):
        write(self.root, "evidence/negative.json", '{"invalid":"untracked"}')
        self._binding("negative", False)
        actual = harness.run_output_pair_preflight(self.root, self.request)
        self.assertEqual(actual["status"], "BLOCKED")

    def test_old_pack_harness_unchanged(self):
        self.assertEqual(harness.RESULT_SCHEMA, "LF_PACK_VALIDATION_RESULT_V1")
        self.assertTrue(callable(harness.evaluate))


if __name__ == "__main__":
    unittest.main(verbosity=2)
