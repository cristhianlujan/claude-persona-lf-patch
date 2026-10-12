import copy
import unittest

from profile_runtime_api.router_source_receipt import (
    SourceReceiptError, validate_aggregate_receipt,
)

EXPECTED = {f"A{i}": f"{i:064x}" for i in range(1, 10)}
VALID = {
    "authority": "CURRENTNESS_AUTHORITY@1.0.0",
    "current_release_verified": True,
    "runtime_consumption_verified": True,
    "router_binding": "verified-router-binding",
    "stage_sha256": EXPECTED,
}


class AggregateReceiptTests(unittest.TestCase):
    def test_valid(self):
        self.assertTrue(validate_aggregate_receipt(copy.deepcopy(VALID), EXPECTED))

    def test_missing_stage(self):
        r = copy.deepcopy(VALID)
        del r["stage_sha256"]["A9"]
        with self.assertRaisesRegex(SourceReceiptError, "COVERAGE"):
            validate_aggregate_receipt(r, EXPECTED)

    def test_wrong_digest(self):
        r = copy.deepcopy(VALID)
        r["stage_sha256"]["A3"] = "f" * 64
        with self.assertRaisesRegex(SourceReceiptError, "MISMATCH"):
            validate_aggregate_receipt(r, EXPECTED)

    def test_stale(self):
        r = copy.deepcopy(VALID)
        r["current_release_verified"] = False
        with self.assertRaisesRegex(SourceReceiptError, "NOT_CURRENT"):
            validate_aggregate_receipt(r, EXPECTED)

    def test_no_router_binding(self):
        r = copy.deepcopy(VALID)
        r["router_binding"] = ""
        with self.assertRaisesRegex(SourceReceiptError, "BINDING"):
            validate_aggregate_receipt(r, EXPECTED)

    def test_not_consumed(self):
        r = copy.deepcopy(VALID)
        r["runtime_consumption_verified"] = False
        with self.assertRaisesRegex(SourceReceiptError, "NOT_CONSUMED"):
            validate_aggregate_receipt(r, EXPECTED)


if __name__ == "__main__":
    unittest.main()
