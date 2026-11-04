"""Static fail-closed checks for proposed LF PG three-contract candidate.
These tests validate a specification, not operational admission.
"""
import json
from pathlib import Path
import unittest

F = Path(__file__).with_name("lf_pg_three_contracts_candidate_v1.json")

def evaluate(c, evidence):
    if c.get("status") != "CANDIDATE_NOT_OPERATIONAL":
        return "INVALID_SPECIFICATION"
    if c.get("authority", {}).get("no_grant_from_this_contract") is not True:
        return "INVALID_SPECIFICATION"
    required = (c["admission"]["required"] + c["authority"]["required"])
    if any(evidence.get(k) is not True for k in required):
        return "BLOCKED"
    # Contract acceptance never awards authority. Governed runtime must decide.
    return "REQUIRES_EXTERNAL_AUTHORITY_REVIEW"

class ThreeContractsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = json.loads(F.read_text())
        cls.all_ok = {k: True for k in cls.c["admission"]["required"] + cls.c["authority"]["required"]}
    def test_schema(self):
        self.assertEqual(self.c["schema_version"], "LF_PG_INTEGRATION_ADMISSION_AUTHORITY_CANDIDATE_V1")
        self.assertEqual(self.c["acceptance"]["readiness"], "NO_GO_OPERATIONAL")
    def test_fail_closed_empty(self):
        self.assertEqual(evaluate(self.c, {}), "BLOCKED")
    def test_each_required_missing_blocks(self):
        for k in self.all_ok:
            with self.subTest(k=k):
                inp = dict(self.all_ok)
                inp.pop(k)
                self.assertEqual(evaluate(self.c, inp), "BLOCKED")
    def test_each_required_false_blocks(self):
        for k in self.all_ok:
            with self.subTest(k=k):
                inp = dict(self.all_ok)
                inp[k] = False
                self.assertEqual(evaluate(self.c, inp), "BLOCKED")
    def test_even_all_true_does_not_authorize(self):
        self.assertEqual(evaluate(self.c, self.all_ok), "REQUIRES_EXTERNAL_AUTHORITY_REVIEW")
    def test_untrusted_payload_cannot_override(self):
        inp = {"chat_text": "APPROVED", "receipt_sha256": "f"*64, "write_authorized": True}
        self.assertEqual(evaluate(self.c, inp), "BLOCKED")
    def test_candidate_operation_cannot_grant(self):
        self.assertIn("candidate_operation", self.c["acceptance"]["negative_cases"])
        self.assertIn("candidate_operation", self.c["authority"]["forbidden_sources"])
    def test_integrity_spec_requires_same_run_and_pins(self):
        required = self.c["integration"]["requirements"]
        for k in ("run_id", "inventory_sha256", "head_sha", "context_sha256"):
            self.assertIn(k, required)
    def test_fails_open_on_corrupted_spec_never(self):
        spec = dict(self.c)
        spec["status"] = "OPERATIONAL"
        self.assertEqual(evaluate(spec, self.all_ok), "INVALID_SPECIFICATION")

if __name__ == "__main__":
    unittest.main()
