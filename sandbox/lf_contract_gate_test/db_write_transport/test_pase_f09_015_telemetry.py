from __future__ import annotations

import unittest
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from pase_f09_015_telemetry import (
    MAX_ENVELOPE_BYTES, StageMetrics, make_envelope, record_failure_once,
    retry_chains, serialize_envelope, sql_measurement_family, verify_execution,
)


class PaseF09015TelemetryTest(unittest.TestCase):
    def identity(self):
        return {"run_kind": "TRAIN", "suite_id": "LF_MIGRATION_MERGE_TRAIN",
                "repository": "cristhianlujan/claude-persona-lf-patch", "pr": "10",
                "git_head_sha": "a" * 40, "github_run_id": "123", "github_run_attempt": "1",
                "train_run_id": "123", "execution_id": "EXEC-1", "migration_version": "20261014000000",
                "source_blob": "b" * 40, "source_sha256": "c" * 64, "control_id": "MIGRATION:1"}

    def metrics(self):
        metrics = StageMetrics()
        metrics.queries.mark_empty()
        metrics.transport.mark_empty()
        metrics.evidence_persistence.mark_empty()
        metrics.control_execution.add(0.001, 10)
        metrics.judges.add(0.001, 10)
        return metrics

    def envelope(self, step="patch", *, observed_stages=None, failure=None):
        value = make_envelope(step=step, started_at="2026-10-14T10:00:00Z",
                              finished_at="2026-10-14T10:00:01Z", execution_id="EXEC-1",
                              control_id="MIGRATION:1", input_value={"x": 1}, result_value={"ok": True},
                              metrics=self.metrics(), run_identity=self.identity(),
                              observed_stages=observed_stages)
        value["evidence_locator"] = "public.lf_operation_execution_steps:EXEC-1:" + step
        if failure:
            value["failure"] = failure
            value["evidence_locator"] = failure["evidence_locator"]
        return value

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
            envelope = self.envelope(name)
            steps.append({"step_id": name, "status": "PASS_CLEAN",
                          "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}})
        with self.assertRaisesRegex(ValueError, "REQUIRED_STEP_MISSING:patch"):
            verify_execution({"execution_id": "EXEC-1", "steps": steps})

    def test_failure_receipt_allows_guard_rejected_patch_row(self):
        preflight = self.envelope("preflight")
        failure_envelope = self.envelope("patch", failure={"code": "PZ015", "evidence_locator": "github-run:123"})
        result = verify_execution({"execution_id": "EXEC-1", "steps": [{"step_id": "preflight",
            "status": "PASS_CLEAN", "evidence_payload": {"pase_f09_015_telemetry_v1": preflight}}],
            "failure_receipt": {"failed_step": "patch", "failure_row_rejection": "guard rejected",
                                "original_error": {"code": "PZ015", "evidence_locator": "github-run:123"},
                                "failure_telemetry": failure_envelope}})
        self.assertTrue(result["failure_row_rejected"])
        self.assertEqual(result["not_reached"], ["verify"])

    def test_rejected_failure_row_without_telemetry_fails_closed(self):
        preflight = self.envelope("preflight")
        with self.assertRaisesRegex(ValueError, "FAILURE_TELEMETRY_MISSING"):
            verify_execution({"execution_id": "EXEC-1", "steps": [{"step_id": "preflight",
                "status": "PASS_CLEAN", "evidence_payload": {"pase_f09_015_telemetry_v1": preflight}}],
                "failure_receipt": {"failed_step": "patch", "failure_row_rejection": "guard rejected",
                                    "original_error": {"code": "PZ015", "evidence_locator": "github-run:123"}}})

    def test_retry_chain_is_ordered_by_time_and_scoped_to_pr_version(self):
        chain = retry_chains([
            {"pr": 9, "migration_version": "20261014000000", "execution_id": "e2", "created_at": "2026-10-14T02:00Z"},
            {"pr": 9, "migration_version": "20261014000000", "execution_id": "e1", "created_at": "2026-10-14T01:00Z"},
            {"pr": 10, "migration_version": "20261014000000", "execution_id": "e3", "created_at": "2026-10-14T03:00Z"},
        ])
        self.assertEqual([x["execution_id"] for x in chain[0]["executions"]], ["e1", "e2"])
        self.assertTrue(all("attempt_number" not in x and "retry_of_execution_id" not in x
                            for group in chain for x in group["executions"]))
        self.assertEqual(len(chain), 2)

    def test_six_stage_envelope_is_correlated_and_within_cap(self):
        envelope = self.envelope()
        raw = serialize_envelope(envelope)
        self.assertLessEqual(len(raw.encode("utf-8")), MAX_ENVELOPE_BYTES)
        self.assertEqual(set(envelope["stages"]), {"transport", "queries", "control_execution", "judges", "evidence_persistence", "total"})
        self.assertEqual(envelope["stages"]["queries"]["count"], 0)
        self.assertEqual(envelope["exact_head_checks"]["measurement"], "OUTSIDE_STAGE")

    def test_sql_write_and_read_round_trips_have_exclusive_buckets(self):
        read_sql = "select status from public.lf_operation_execution_steps where execution_id = :'exec';"
        write_sql = "select public.lf_record_db_operation_step_v1(:'exec', :'step', :'ref', '{}'::jsonb, :'actor');"
        self.assertEqual(sql_measurement_family(read_sql), "queries")
        self.assertEqual(sql_measurement_family(write_sql), "evidence_persistence")

    def test_unobserved_required_stage_fails_closed(self):
        envelope = self.envelope(observed_stages={"judges": {"count": 1, "duration_ms": "NOT_OBSERVED", "bytes": 0}})
        execution = {"execution_id": "EXEC-1", "steps": [{"step_id": "patch", "status": "PASS_CLEAN",
            "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}}]}
        with self.assertRaisesRegex(ValueError, "STAGE_NOT_OBSERVED:patch:judges"):
            verify_execution(execution)

    def test_mismatch_run_identity_fails_closed(self):
        envelope = self.envelope()
        execution = {"execution_id": "EXEC-1", "repository": "other/repo", "steps": [{"step_id": "patch", "status": "PASS_CLEAN",
            "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}}]}
        with self.assertRaisesRegex(ValueError, "RUN_IDENTITY_MISMATCH:patch:repository"):
            verify_execution(execution)

    def test_failure_verdict_and_locator_are_required(self):
        envelope = self.envelope(failure={"code": "PZ015", "evidence_locator": "github-run:123"})
        preflight = self.envelope("preflight")
        execution = {"execution_id": "EXEC-1", "steps": [
            {"step_id": "preflight", "status": "PASS_CLEAN",
             "evidence_payload": {"pase_f09_015_telemetry_v1": preflight}},
            {"step_id": "patch", "status": "FAILURE",
             "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}}]}
        result = verify_execution(execution)
        self.assertEqual(result["failed_step"], "patch")


if __name__ == "__main__":
    unittest.main()
