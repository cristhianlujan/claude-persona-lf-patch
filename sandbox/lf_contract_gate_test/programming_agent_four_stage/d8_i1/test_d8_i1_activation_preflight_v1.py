import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("d8", Path(__file__).with_name("d8_i1_activation_preflight_v1.py"))
d8 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d8)


def fixture():
    return {"router_candidate": dict(d8.CANDIDATE),
            "operation_registered": False,
            "evidence": {k: "fixture://untrusted/" + k for k in d8.REQUIRED}}


class PreflightTests(unittest.TestCase):
    def check(self, v):
        out = d8.inspect(v)
        self.assertEqual(out["verdict"], "BLOCKED")
        self.assertEqual(out["authority"], "NONE")
        self.assertFalse(out["activate_allowed"])
        self.assertIn("I1_OWNER_ACTIVATION_DECISION_REQUIRED", out["reason_codes"])
        return out["reason_codes"]

    def test_coherent_fixture_never_authorizes(self):
        self.assertIn("EVIDENCE_PROVENANCE_NOT_AUTHENTICATED", self.check(fixture()))

    def test_null_snapshot(self):
        self.assertIn("INVALID_SNAPSHOT", self.check(None))

    def test_empty(self):
        self.assertIn("D8_CANDIDATE_MISMATCH", self.check({}))

    def test_fake_active(self):
        s = fixture(); s["router_candidate"]["status"] = "ACTIVE"
        self.assertIn("D8_CANDIDATE_MISMATCH", self.check(s))

    def test_write_permission_flip(self):
        s = fixture(); s["router_candidate"]["write_allowed"] = True
        self.assertIn("D8_CANDIDATE_MISMATCH", self.check(s))

    def test_wrong_operation(self):
        s = fixture(); s["router_candidate"]["operation_code"] = "OTHER"
        self.assertIn("D8_CANDIDATE_MISMATCH", self.check(s))

    def test_missing_dispatcher(self):
        s = fixture(); del s["evidence"]["authorized_dispatcher"]
        self.assertIn("MISSING_AUTHORIZED_DISPATCHER", self.check(s))

    def test_boolean_pass_not_evidence(self):
        s = fixture(); s["evidence"]["reviewer_approval"] = True
        self.assertIn("MISSING_REVIEWER_APPROVAL", self.check(s))

    def test_fake_operation_exists(self):
        s = fixture(); s["operation_registered"] = True
        self.assertIn("OPERATION_REGISTRY_REVALIDATION_REQUIRED", self.check(s))

    def test_extra_authority_flag(self):
        s = fixture(); s["activate"] = True
        self.assertIn("SNAPSHOT_FIELDS_MISMATCH", self.check(s))

    def test_cyclic_evidence(self):
        s = fixture(); loop = []; loop.append(loop)
        s["evidence"]["smoke_evidence"] = loop
        self.assertIn("MISSING_SMOKE_EVIDENCE", self.check(s))

if __name__ == "__main__":
    unittest.main()
