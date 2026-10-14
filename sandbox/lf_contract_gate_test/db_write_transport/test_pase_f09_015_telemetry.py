from __future__ import annotations

import unittest
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lf_train_execution_recorder as train_recorder

from pase_f09_015_telemetry import (
    MAX_ENVELOPE_BYTES, TELEMETRY_STAGES, NOT_OBSERVED, StageMetrics, make_envelope, record_failure_once,
    retry_chains, serialize_envelope, verify_execution,
    sql_measurement_family,
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

    def envelope(self, step="patch", execution_id="EXEC-1", omit_stage=None, total_started_at=None):
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
                             observed_stages=observed_stages, total_started_at=total_started_at)

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
        self.assertEqual(self.envelope()["exact_head_checks"]["measurement"], "OUTSIDE_STAGE")

    def test_sql_write_round_trip_is_evidence_persistence_not_query(self):
        write = "select public.lf_record_db_operation_step_v1(:'exec', :'step');"
        read = "select status from public.lf_operation_execution_steps where execution_id = :'exec';"
        self.assertEqual(sql_measurement_family(write), "evidence_persistence")
        self.assertEqual(sql_measurement_family(read), "queries")
        # A call has one family only, so its measured duration cannot be added
        # to both counters and inflate the combined budget.
        self.assertNotEqual(sql_measurement_family(write), "queries")

    def test_pending_round_trips_survive_train_state_handoff(self):
        metrics = StageMetrics()
        metrics.queries.add(1.25, 40)
        metrics.evidence_persistence.add(2.5, 80)
        state = train_recorder.telemetry_metrics_to_state(metrics)
        restored = train_recorder.telemetry_metrics_from_state(state)
        self.assertEqual(restored.queries.fields(), metrics.queries.fields())
        self.assertEqual(restored.evidence_persistence.fields(), metrics.evidence_persistence.fields())

    def test_exact_head_check_boundary_is_required(self):
        execution = self.execution()
        del execution["steps"][1]["evidence_payload"]["pase_f09_015_telemetry_v1"]["exact_head_checks"]
        with self.assertRaisesRegex(ValueError, "EXACT_HEAD_CHECKS_BOUNDARY_MISSING:patch"):
            verify_execution(execution)

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

    def test_total_stage_spans_train_start_through_terminal_step(self):
        envelope = self.envelope(step="verify", total_started_at="2026-10-14T09:59:00Z")
        self.assertEqual(envelope["stages"]["total"]["duration_ms"], 61000.0)

    def test_six_stage_telemetry_covers_success_failure_and_retry(self):
        success = self.execution()
        self.assertEqual(verify_execution(success)["status"], "PASS")

        failed = self.execution()
        failed["steps"] = failed["steps"][:2]
        failed["steps"][1]["status"] = "BLOCKED_BY_ENFORCEMENT"
        self.assertEqual(verify_execution(failed)["status"], "FAILURE_PATH_RECONSTRUCTED")

        retried = self.execution()
        attempts = retry_chains([
            {"pr": 12, "migration_version": "20261014000000", "execution_id": "EXEC-1",
             "created_at": "2026-10-14T10:00:00Z"},
            {"pr": 12, "migration_version": "20261014000000", "execution_id": "EXEC-2",
             "created_at": "2026-10-14T10:01:00Z"},
        ])
        self.assertEqual([x["execution_id"] for x in attempts[0]["attempts"]], ["EXEC-1", "EXEC-2"])
        for run in (success, failed, retried):
            for row in run["steps"]:
                envelope = row["evidence_payload"]["pase_f09_015_telemetry_v1"]
                self.assertEqual(set(envelope["stages"]), set(TELEMETRY_STAGES))
                for stage in TELEMETRY_STAGES:
                    self.assertIsInstance(envelope["stages"][stage]["duration_ms"], (int, float), stage)

    def test_recorder_emits_six_observed_stages_for_success_failure_and_retry(self):
        original_call = train_recorder.call
        original_metrics = train_recorder._TELEMETRY_METRICS
        original_started = train_recorder._TELEMETRY_STARTED_AT
        original_train_started = train_recorder._TELEMETRY_TRAIN_STARTED_AT
        captured = []
        def fake_call(sql, **params):
            if "lf_record_db_operation_step_v1" in sql:
                captured.append(json.loads(params["payload"]))
                # The real call() records this completed durable round-trip
                # after the immutable envelope has been serialized.
                train_recorder._TELEMETRY_METRICS.evidence_persistence.add(0.4, 24)
                status = "BLOCKED_BY_ENFORCEMENT" if "blocking_codes" in params.get("payload", "") else "PASS_CLEAN"
                return {"outcome": "STEP_RECORDED", "status": status}
            return {}
        try:
            train_recorder.call = fake_call
            for attempt, blocked in ((1, False), (2, True), (3, False)):
                train_recorder._TELEMETRY_METRICS = StageMetrics()
                train_recorder._TELEMETRY_METRICS.queries.add(0.2, 12)
                train_recorder._TELEMETRY_METRICS.transport.add(0.3, 14)
                train_recorder._TELEMETRY_METRICS.evidence_persistence.add(0.1, 8)
                train_recorder._TELEMETRY_STARTED_AT = "2026-10-14T10:00:00Z"
                train_recorder._TELEMETRY_TRAIN_STARTED_AT = "2026-10-14T09:59:00Z"
                ids = {"execution_id": f"EXEC-{attempt}", "effect_scope": "MIGRATION:20261014000000",
                       "actor": "TRAIN-RUN-1"}
                ctx = {"repo": "owner/repo", "pr": "12", "head_sha": "a" * 40,
                       "run_id": str(345 + attempt), "version": "20261014000000",
                       "source_blob": "b" * 40, "source_sha256": "c" * 64}
                evidence = {"exact_target": {"head": "a" * 40}, "write_receipt": {"ok": True}}
                if blocked:
                    evidence.update({"blocking_codes": ["TEST_BLOCK"], "failure": {"code": "TEST_BLOCK"}})
                result = train_recorder.record_step(ids, "patch", evidence, ctx=ctx)
                self.assertEqual(result["outcome"], "STEP_RECORDED")
                envelope = captured[-1]["pase_f09_015_telemetry_v1"]
                self.assertEqual(set(envelope["stages"]), set(TELEMETRY_STAGES))
                for stage in TELEMETRY_STAGES:
                    self.assertIsInstance(envelope["stages"][stage]["duration_ms"], (int, float), stage)
        finally:
            train_recorder.call = original_call
            train_recorder._TELEMETRY_METRICS = original_metrics
            train_recorder._TELEMETRY_STARTED_AT = original_started
            train_recorder._TELEMETRY_TRAIN_STARTED_AT = original_train_started
        self.assertEqual(len(captured), 3)

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
