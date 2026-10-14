from __future__ import annotations

import unittest
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lf_train_execution_recorder as train_recorder

from pase_f09_015_telemetry import (
    MAX_ENVELOPE_BYTES, TELEMETRY_STAGES, NOT_OBSERVED, StageMetrics, make_envelope, record_failure_once,
    retry_chains, serialize_envelope, verify_execution,
)


class PaseF09015TelemetryTest(unittest.TestCase):
    def identity(self, execution_id="EXEC-1"):
        return {"run_kind": "TRAIN", "suite_id": "LF_MIGRATION_MERGE_TRAIN",
                "repository": "owner/repo", "pr": "12",
                "git_head_sha": "a" * 40, "github_run_id": "345", "github_run_attempt": "1",
                "train_run_id": "345",
                "execution_id": execution_id, "migration_version": "20261014000000",
                "source_blob": "b" * 40, "source_sha256": "c" * 64,
                "control_id": "MIGRATION:20261014000000"}

    def envelope(self, step="patch", execution_id="EXEC-1", omit_stage=None):
        metrics = StageMetrics()
        metrics.queries.add(0.25, 16)
        metrics.transport.add(0.5, 32)
        observed_stages = {name: {"count": 1, "duration_ms": 0.75, "bytes": 8}
                           for name in TELEMETRY_STAGES
                           if name not in ("queries", "transport", "total", omit_stage)}
        return make_envelope(step=step, started_at="2026-10-14T10:00:00Z",
                             finished_at="2026-10-14T10:00:01Z", execution_id=execution_id,
                             control_id="MIGRATION:1", input_value={"x": 1}, result_value={"ok": True},
                             metrics=metrics, run_identity=self.identity(execution_id),
                             observed_stages=observed_stages)

    def execution(self, omit_stage=None):
        rows = []
        for step in ("preflight", "patch", "verify"):
            envelope = self.envelope(step=step, omit_stage=omit_stage if step == "patch" else None)
            rows.append({"step_id": step, "status": "PASS_CLEAN",
                         "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}})
        return {"execution_id": "EXEC-1", "steps": rows}

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
            envelope = self.envelope(step=name)
            steps.append({"step_id": name, "status": "PASS_CLEAN",
                          "evidence_payload": {"pase_f09_015_telemetry_v1": envelope}})
        with self.assertRaisesRegex(ValueError, "REQUIRED_STEP_MISSING:patch"):
            verify_execution({"execution_id": "EXEC-1", "steps": steps})

    def test_failure_receipt_allows_guard_rejected_patch_row(self):
        preflight = self.envelope(step="preflight")
        result = verify_execution({"execution_id": "EXEC-1", "steps": [{"step_id": "preflight",
            "status": "PASS_CLEAN", "evidence_payload": {"pase_f09_015_telemetry_v1": preflight}}],
            "failure_receipt": {"failed_step": "patch", "failure_row_rejection": "guard rejected"}})
        self.assertTrue(result["failure_row_rejected"])
        self.assertEqual(result["not_reached"], ["verify"])

    def test_success_requires_all_six_emitted_stages(self):
        result = verify_execution(self.execution())
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["steps"], ["preflight", "patch", "verify"])
        self.assertEqual(set(self.envelope()["stages"]), set(TELEMETRY_STAGES))

    def test_train_identity_binds_run_attempt_head_and_migration_source(self):
        ctx = {"repo": "owner/repo", "pr": "12", "head_sha": "a" * 40,
               "run_id": "345", "version": "20261014000000", "source_blob": "b" * 40,
               "source_sha256": "c" * 64}
        ids = {"execution_id": "EXEC-DB-TRAIN-PR12-20261014000000-R345",
               "effect_scope": "MIGRATION:20261014000000"}
        value = train_recorder.telemetry_run_identity(ctx, ids)
        self.assertEqual(value["run_kind"], "TRAIN")
        self.assertEqual(value["suite_id"], "LF_MIGRATION_MERGE_TRAIN")
        self.assertEqual(value["execution_id"], ids["execution_id"])
        self.assertEqual(value["github_run_id"], "345")
        self.assertEqual(value["train_run_id"], "345")
        self.assertEqual(value["git_head_sha"], "a" * 40)
        self.assertEqual(value["source_blob"], "b" * 40)

    def test_unemitted_stage_is_not_observed_and_verifier_fails_closed(self):
        execution = self.execution(omit_stage="judges")
        envelope = execution["steps"][1]["evidence_payload"]["pase_f09_015_telemetry_v1"]
        self.assertEqual(envelope["stages"]["judges"]["duration_ms"], NOT_OBSERVED)
        with self.assertRaisesRegex(ValueError, "STAGE_NOT_OBSERVED:patch:judges"):
            verify_execution(execution)

    def test_retry_chain_is_ordered_by_time_and_scoped_to_pr_version(self):
        chain = retry_chains([
            {"pr": 9, "migration_version": "20261014000000", "execution_id": "e2", "created_at": "2026-10-14T02:00Z"},
            {"pr": 9, "migration_version": "20261014000000", "execution_id": "e1", "created_at": "2026-10-14T01:00Z"},
            {"pr": 10, "migration_version": "20261014000000", "execution_id": "e3", "created_at": "2026-10-14T03:00Z"},
        ])
        self.assertEqual([x["execution_id"] for x in chain[0]["attempts"]], ["e1", "e2"])
        self.assertEqual(len(chain), 2)


if __name__ == "__main__":
    unittest.main()
