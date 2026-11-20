import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).with_name("pg01_pg02_pre_admission_v1.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def fixture():
    return {
        "plan_code": bridge.PLAN,
        "units": {
            "PG-01": {"work_code": "PROG-REM-001", "status": "DONE"},
            "PG-02": {"work_code": "PROG-REM-002", "status": "DONE"},
        },
        "dependencies": [{"work_code": "PROG-REM-002",
                          "requires_work": "PROG-REM-001",
                          "relation_type": "REQUIRES"}],
        "pg01_receipt": {"proposal_id": "P-1", "result": "PASS"},
        "bindings": [{"checkpoint_code": "PG-01_C1", "validation_code": "SYNTHETIC"}],
        "dispatcher": {"handler": "synthetic"},
    }


class BridgeTests(unittest.TestCase):
    def check(self, snapshot):
        x = bridge.qualify(snapshot)
        self.assertEqual(x["verdict"], "BLOCKED")
        self.assertEqual(x["authority"], "NONE")
        self.assertFalse(x["dispatch_allowed"])
        self.assertIn("AUTHENTICATED_DISPATCH_HANDLER_REQUIRED", x["reason_codes"])
        return x["reason_codes"]

    def test_coherent_fixture_never_authorizes(self):
        self.assertIn("DISPATCH_HANDLER_UNATTESTED", self.check(fixture()))

    def test_missing_snapshot(self):
        self.assertIn("INVALID_SNAPSHOT", self.check(None))

    def test_wrong_plan(self):
        x = fixture(); x["plan_code"] = "OTHER"
        self.assertIn("PLAN_MISMATCH", self.check(x))

    def test_missing_receipt(self):
        x = fixture(); x["pg01_receipt"] = None
        self.assertIn("PG01_RECEIPT_MISSING", self.check(x))

    def test_self_declared_pass(self):
        x = fixture(); x["pg01_receipt"] = {"proposal_id": "P-1", "result": "PASS", "approved": True}
        self.assertIn("PG01_RECEIPT_AUTHENTICITY_UNVERIFIED", self.check(x))

    def test_no_bindings(self):
        x = fixture(); x["bindings"] = []
        self.assertIn("PG_VALIDATOR_BINDINGS_MISSING", self.check(x))

    def test_wrong_dependency(self):
        x = fixture(); x["dependencies"] = []
        self.assertIn("PG02_DEPENDENCY_NOT_VERIFIED", self.check(x))

    def test_pg01_pending(self):
        x = fixture(); x["units"]["PG-01"]["status"] = "BACKLOG"
        self.assertIn("UNIT_NOT_DONE_PG_01", self.check(x))

    def test_unidentified_dispatcher(self):
        x = fixture(); x["dispatcher"] = None
        self.assertIn("DISPATCH_HANDLER_NOT_IDENTIFIED", self.check(x))

    def test_extra_authority_flag(self):
        x = fixture(); x["go_write"] = True
        self.assertIn("SNAPSHOT_FIELDS_MISMATCH", self.check(x))

    def test_cyclic_unit_field_fails_closed(self):
        x = fixture(); cycle = []; cycle.append(cycle)
        x["units"]["PG-01"]["status"] = cycle
        self.assertIn("UNIT_NOT_DONE_PG_01", self.check(x))


if __name__ == "__main__":
    unittest.main()
