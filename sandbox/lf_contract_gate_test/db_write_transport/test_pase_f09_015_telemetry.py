from __future__ import annotations

import unittest
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from pase_f09_015_telemetry import (
    MAX_ENVELOPE_BYTES, StageMetrics, make_envelope, record_failure_once,
    retry_chains, serialize_envelope, verify_execution,
)


class PaseF09015TelemetryTest(unittest.TestCase):
    def envelope(self):
        return make_envelope(step="patch", started_at="2026-10-14T10:00:00Z",
                             finished_at="2026-10-14T10:00:01Z", execution_id="EXEC-1",
                             control_id="MIGRATION:1", input_value={"x": 1}, result_value={"ok": True},
                             metrics=StageMetrics())

    def test_envelope_within_and_over_byte_cap(self):
        raw = serialize_envelope(self.envelope())
        self.assertLessEqual(len(raw.encode("utf-8")), MAX_ENVELOPE_BYTES)
        oversized = self.envelope()
        oversized["extra"] = "x" * MAX_ENVELOPE_BYTES
        with self.assertRaisesRegex(ValueError, "ENVELOPE_TOO_LARGE"):
            serialize_envelope(oversized)

    def test_failure_row_accepted(self):
        calls = []
        result = record_failure_once(lambda error: calls.append(error) or "recorded",
                                     lambda receipt: self.fail("receipt should not be appended"),
                                     {"code": "PZ015", "message": "controlled failure"})
        self.assertEqual(result["outcome"], "FAILURE_ROW_RECORDED")
        self.assertEqual(len(calls), 1)

    def test_failure_row_rejected_preserves_original_without_retry(self):
        attempts, receipts = [], []
        def rejected(_error):
            attempts.append(1)
            raise RuntimeError("GUARD_REJECTED:missing evidence")
        result = record_failure_once(rejected, receipts.append,
                                     {"code": "PZ015", "sqlstate": "PZ015", "message": "original failure"})
        self.assertEqual(result["outcome"], "FAILURE_ROW_REJECTED")
        self.assertEqual(len(attempts), 1)
        self.assertEqual(receipts[0]["original_error"]["code"], "PZ015")
        self.assertIn("GUARD_REJECTED", receipts[0]["failure_row_rejected"])

    def test_missing_required_step_fails_closed(self):
        steps = []
        for name in ("preflight", "verify"):
            envelope = make_envelope(step=name, started_at="2026-10-14T10:00:00Z",
                                     finished_at="2026-10-14T10:00:01Z", execution_id="EXEC-1",
                                     control_id="MIGRATION:1", input_value={}, result_value={})
            steps.append({"step_id": name, "status": "PASS_CLEAN",
                          "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}})
        with self.assertRaisesRegex(ValueError, "REQUIRED_STEP_MISSING:patch"):
            verify_execution({"execution_id": "EXEC-1", "steps": steps})

    def test_failure_receipt_allows_guard_rejected_patch_row(self):
        preflight = make_envelope(step="preflight", started_at="2026-10-14T10:00:00Z",
                                  finished_at="2026-10-14T10:00:01Z", execution_id="EXEC-1",
                                  control_id="MIGRATION:1", input_value={}, result_value={})
        result = verify_execution({"execution_id": "EXEC-1", "steps": [{"step_id": "preflight",
            "status": "PASS_CLEAN", "evidence_payload": {"pase_f09_015_telemetry_v1": preflight}}],
            "failure_receipt": {"failed_step": "patch", "failure_row_rejection": "guard rejected"}})
        self.assertTrue(result["failure_row_rejected"])
        self.assertEqual(result["not_reached"], ["verify"])

    def test_retry_chain_survives_version_reassignment(self):
        chain = retry_chains([
            {"pr": 9, "migration_name": "lf_c3_v1", "migration_version": "20261014000500",
             "execution_id": "e2", "created_at": "2026-10-14T02:00Z"},
            {"pr": 9, "migration_name": "lf_c3_v1", "migration_version": "20261014000000",
             "execution_id": "e1", "created_at": "2026-10-14T01:00Z"},
        ])
        self.assertEqual(len(chain), 1)
        self.assertEqual([x["execution_id"] for x in chain[0]["attempts"]], ["e1", "e2"])
        self.assertEqual([x["migration_version"] for x in chain[0]["attempts"]],
                         ["20261014000000", "20261014000500"])

    def test_retry_chain_separates_names_and_prs(self):
        chain = retry_chains([
            {"pr": 9, "migration_name": "lf_a_v1", "migration_version": "20261014000000", "execution_id": "e1", "created_at": "1"},
            {"pr": 9, "migration_name": "lf_b_v1", "migration_version": "20261014000000", "execution_id": "e2", "created_at": "2"},
            {"pr": 10, "migration_name": "lf_a_v1", "migration_version": "20261014000000", "execution_id": "e3", "created_at": "3"},
        ])
        self.assertEqual(len(chain), 3)

    def test_retry_chain_name_from_path_and_version_prefix(self):
        chain = retry_chains([
            {"pr": 9, "migration_path": "supabase/migrations/20261014000000_lf_a_v1.sql", "execution_id": "e1", "created_at": "1"},
            {"pr": 9, "migration_name": "20261014000500_lf_a_v1", "execution_id": "e2", "created_at": "2"},
        ])
        self.assertEqual(len(chain), 1)
        self.assertEqual(chain[0]["migration_name"], "lf_a_v1")

    def test_retry_chain_missing_name_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "RETRY_CHAIN_MIGRATION_NAME_MISSING"):
            retry_chains([{"pr": 9, "migration_version": "20261014000000", "execution_id": "e1"}])


if __name__ == "__main__":
    unittest.main()
