"""Regression tests for the pre/post-inference aggregate source receipt contract."""
import copy
import unittest

from profile_runtime_api.router_source_receipt import (
    SourceReceiptError,
    validate_aggregate_receipt,
)

EXPECTED = {f"A{i}": f"{i:064x}" for i in range(1, 10)}
VALID = {
    "schema": "lf-governed-aggregate-source-receipt/v1",
    "authority": "CURRENTNESS_AUTHORITY@1.0.0",
    "current_release_verified": True,
    "router_materialization_verified": True,
    "runtime_consumption_verified": False,
    "router_binding": "verified-router-binding",
    "stage_sha256": EXPECTED,
}


class AggregateReceiptTests(unittest.TestCase):
    def test_valid_pre(self):
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

    def test_not_consumed_post(self):
        with self.assertRaisesRegex(SourceReceiptError, "NOT_CONSUMED"):
            validate_aggregate_receipt(copy.deepcopy(VALID), EXPECTED, phase="POST_INFERENCE")

    def test_post_valid(self):
        r = copy.deepcopy(VALID)
        r.update(runtime_consumption_verified=True, execution_receipt_ref="x", model_request_sha256="a" * 64)
        self.assertTrue(validate_aggregate_receipt(r, EXPECTED, phase="POST_INFERENCE"))

    def test_premature(self):
        r = copy.deepcopy(VALID)
        r["runtime_consumption_verified"] = True
        with self.assertRaisesRegex(SourceReceiptError, "PREMATURE"):
            validate_aggregate_receipt(r, EXPECTED)

    def test_unmaterialized(self):
        r = copy.deepcopy(VALID)
        r["router_materialization_verified"] = False
        with self.assertRaisesRegex(SourceReceiptError, "NOT_MATERIALIZED"):
            validate_aggregate_receipt(r, EXPECTED)


if __name__ == "__main__":
    unittest.main()
