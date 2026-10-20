from __future__ import annotations

import copy
import unittest

from verify_train_receipt import ReceiptError, _reports_exit_code, _selector_filter, verify_snapshot

SHA = "a" * 40
MERGE = "f" * 40
VERSION = "20261015152000"
NAME = "lf_example_v1"
EXEC = f"EXEC-DB-TRAIN-PR2754-{VERSION}-R123456"
REPO = "cristhianlujan/claude-persona-lf-patch"


def completed_fixture() -> dict:
    receipt = {
        "schema_version": "LF_MIGRATION_TRAIN_RECEIPT_V1",
        "execution_id": EXEC,
        "train_run_id": "123456",
        "repository": REPO,
        "pr": 2754,
        "terminal_status": "COMPLETED",
        "started_at": "2026-10-15T15:20:00Z",
        "completed_at": "2026-10-15T15:35:00Z",
        "terminated_by": "LF-MIGRATION-TRAIN-RUN-123456",
        "human_authorization": {"label": "ready-to-merge", "authorized_by": "paulozterra",
                                "authorized_head": SHA},
        "heads": {"main_before": "b" * 40, "authorized_head": SHA,
                  "final_head": "c" * 40, "execution_head": "c" * 40,
                  "final_head_is_execution_head": True, "persisted_head": "d" * 40,
                  "main_after": MERGE},
        "diff_check": {"class": "SYNC_AND_RETIMESTAMP_ONLY", "unexpected_paths": []},
        "migration": {"target_code": f"{VERSION}_{NAME}", "path": f"supabase/migrations/{VERSION}_{NAME}.sql",
                      "version": VERSION, "name": NAME, "source_blob": "e" * 40,
                      "source_sha256": "1" * 64},
        "write_ahead": {"effect_scope": f"MIGRATION:{VERSION}",
                        "dispatch_key": "lf-migration-train-run-123456",
                        "request_sha256": "1" * 64},
        "effect": {"phase": "SUCCEEDED", "scope": f"MIGRATION:{VERSION}"},
        "apply": {"code": "APPLIED_EXACT", "executor": "supabase_migrations.schema_migrations",
                  "ledger_version": VERSION, "ledger_name": NAME},
        "ledger_readback": {"version": VERSION, "name": NAME, "matches_target": True},
        "parity": {"migration_source_parity": "PASS"},
        "merge": {"merge_sha": MERGE, "in_main": True},
    }
    return {
        "event": {"id": 10, "evento_tipo": "MIGRATION_TRAIN_RECEIPT_RECORDED",
                  "entidad_codigo": EXEC,
                  "payload": {"receipt_schema": "LF_MIGRATION_TRAIN_RECEIPT_V1",
                              "evidence_schema_version": "operational-event/v2",
                              "receipt_sha256": "2" * 64, "acceptance_declared": False,
                              "receipt": receipt}},
        "receipt_sha_matches": True,
        "execution": {"execution_id": EXEC, "operation_code": "ACTUALIZACION_DB_LF",
                      "target_type": "MIGRATION", "target_repo": REPO,
                      "target_code": f"{VERSION}_{NAME}",
                      "target_path": f"supabase/migrations/{VERSION}_{NAME}.sql",
                      "request_sha256": "1" * 64, "status": "COMPLETED",
                      "manifest": {"pr": 2754, "train_run_id": "123456", "head_sha": "c" * 40}},
        "steps": [
            {"step_id": "preflight", "status": "PASS_CLEAN", "evidence_payload": {
                "exact_target": {"migration_version": VERSION, "migration_name": NAME,
                                 "target_path": f"supabase/migrations/{VERSION}_{NAME}.sql",
                                 "source_blob": "e" * 40, "source_sha256": "1" * 64,
                                 "repository": REPO, "pr": 2754, "head_sha": "c" * 40},
                "schema_source_readback": {"persisted_head_sha": "d" * 40}}},
            {"step_id": "patch", "status": "PASS_CLEAN", "evidence_payload": {
                "db_write_transport_receipt": {"code": "APPLIED_EXACT",
                                                "executor": "supabase_migrations.schema_migrations",
                                                "ledger_version": VERSION, "ledger_name": NAME},
                "write_receipt": {"ledger_version": VERSION, "ledger_name": NAME}}},
            {"step_id": "verify", "status": "PASS_CLEAN", "evidence_payload": {
                "readback": {"in_main": True, "main_merge_sha": MERGE},
                "db_write_transport_readback": {"version": VERSION, "name": NAME}}},
        ],
        "ledger_rows": [{"version": VERSION, "name": NAME}],
        "github_pull": {"number": 2754, "state": "closed", "merged": True,
                         "merge_commit_sha": MERGE,
                         "base": {"ref": "main", "repo": {"full_name": REPO}},
                         "head": {"sha": "c" * 40}},
    }


class TrainReceiptVerifierTest(unittest.TestCase):
    def test_complete_receipt_passes(self):
        self.assertEqual(verify_snapshot(completed_fixture())["result"], "PASS")

    def test_missing_verify_step_fails(self):
        snapshot = completed_fixture()
        snapshot["steps"] = [s for s in snapshot["steps"] if s["step_id"] != "verify"]
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("steps.verify:EXPECTED_ONE_FOUND_0", result["reasons"])

    def test_receipt_version_must_match_ledger(self):
        snapshot = completed_fixture()
        snapshot["ledger_rows"] = [{"version": VERSION, "name": "lf_other_v1"}]
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("schema_migrations:VERSION_NAME_MISMATCH", result["reasons"])

    def test_already_applied_exact_version_and_name_is_accepted(self):
        # Local schema_migrations fixture already contains the exact target row.
        snapshot = completed_fixture()
        snapshot["ledger_rows"] = [{"version": VERSION, "name": NAME}]
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "PASS")

    def test_already_applied_version_with_different_name_fails(self):
        snapshot = completed_fixture()
        snapshot["ledger_rows"] = [{"version": VERSION, "name": "lf_conflicting_v1"}]
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("schema_migrations:VERSION_NAME_MISMATCH", result["reasons"])

    def test_head_sha_must_match_github_source_head(self):
        snapshot = completed_fixture()
        snapshot["github_pull"]["head"]["sha"] = "9" * 40
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("github_pull.head.sha:FINAL_HEAD_MISMATCH", result["reasons"])

    def test_blocked_without_ledger_effect_is_blocked_not_pass(self):
        snapshot = completed_fixture()
        receipt = snapshot["event"]["payload"]["receipt"]
        receipt["terminal_status"] = "BLOCKED"
        receipt.pop("completed_at")
        receipt.pop("apply")
        receipt.pop("merge")
        receipt["effect"] = {"phase": "ABANDONED"}
        receipt["failure"] = {"reason": "APPLY_FAILED_BEFORE_LEDGER_EFFECT",
                              "failed_step": "Apply exact version and ledger readback",
                              "recorded_at": "2026-10-15T15:30:00Z"}
        snapshot["execution"]["status"] = "BLOCKED"
        snapshot["steps"] = snapshot["steps"][:2]
        snapshot["steps"][1]["status"] = "BLOCKED_BY_ENFORCEMENT"
        snapshot["ledger_rows"] = []
        snapshot["github_pull"].update({"state": "open", "merged": False, "merge_commit_sha": None})
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "BLOCKED")
        self.assertNotEqual(result["result"], "PASS")

    def test_blocked_without_failure_recorded_at_fails(self):
        snapshot = completed_fixture()
        receipt = snapshot["event"]["payload"]["receipt"]
        receipt["terminal_status"] = "BLOCKED"
        receipt.pop("completed_at")
        receipt.pop("apply")
        receipt.pop("merge")
        receipt["effect"] = {"phase": "ABANDONED"}
        receipt["failure"] = {"reason": "APPLY_FAILED_BEFORE_LEDGER_EFFECT",
                              "failed_step": "Apply exact version and ledger readback"}
        snapshot["execution"]["status"] = "BLOCKED"
        snapshot["steps"] = snapshot["steps"][:2]
        snapshot["ledger_rows"] = []
        snapshot["github_pull"].update({"state": "open", "merged": False, "merge_commit_sha": None})
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("failure.recorded_at:MISSING", result["reasons"])

    def test_blocked_failure_timestamp_must_have_timezone_and_follow_start(self):
        for timestamp, expected_reason in (
            ("2026-10-15T15:30:00", "failure.recorded_at:INVALID_UTC_TIMESTAMP"),
            ("2026-10-15T15:19:59Z", "receipt.failure.recorded_at:BEFORE_STARTED_AT"),
        ):
            with self.subTest(timestamp=timestamp):
                snapshot = completed_fixture()
                receipt = snapshot["event"]["payload"]["receipt"]
                receipt["terminal_status"] = "BLOCKED"
                receipt.pop("completed_at")
                receipt.pop("apply")
                receipt.pop("merge")
                receipt["effect"] = {"phase": "ABANDONED"}
                receipt["failure"] = {"reason": "APPLY_FAILED_BEFORE_LEDGER_EFFECT",
                                      "failed_step": "Apply exact version and ledger readback",
                                      "recorded_at": timestamp}
                snapshot["execution"]["status"] = "BLOCKED"
                snapshot["steps"] = snapshot["steps"][:2]
                snapshot["ledger_rows"] = []
                snapshot["github_pull"].update({"state": "open", "merged": False, "merge_commit_sha": None})
                result = verify_snapshot(snapshot)
                self.assertEqual(result["result"], "FAIL")
                self.assertIn(expected_reason, result["reasons"])

    def test_receipt_hash_mismatch_fails_closed(self):
        snapshot = completed_fixture()
        snapshot["receipt_sha_matches"] = False
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("receipt_sha256:NOT_VERIFIED", result["reasons"])

    def test_missing_required_timestamp_fails_closed(self):
        snapshot = completed_fixture()
        del snapshot["event"]["payload"]["receipt"]["completed_at"]
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("receipt.completed_at:MISSING", result["reasons"])

    def test_completed_unexpected_diff_class_fails(self):
        snapshot = completed_fixture()
        snapshot["event"]["payload"]["receipt"]["diff_check"]["class"] = "UNEXPECTED_CHANGES"
        result = verify_snapshot(snapshot)
        self.assertEqual(result["result"], "FAIL")
        self.assertIn("diff_check.class:COMPLETED_NOT_CLEAN", result["reasons"])


    def test_merge_sha_selector_binds_exact_receipt(self):
        sql_filter, arg, kind = _selector_filter(
            pr=None, execution_id=None, merge_sha=MERGE,
        )
        self.assertEqual(
            sql_filter,
            "ev.payload->'receipt'->'merge'->>'merge_sha' = %s",
        )
        self.assertEqual(arg, MERGE)
        self.assertEqual(kind, "merge_sha")

    def test_merge_sha_selector_rejects_invalid_sha(self):
        with self.assertRaisesRegex(ReceiptError, "INVALID_MERGE_SHA"):
            _selector_filter(pr=None, execution_id=None, merge_sha="not-a-sha")

    def test_merge_sha_missing_or_duplicate_fails_closed(self):
        with self.assertRaisesRegex(ReceiptError, "TRAIN_RECEIPT_MERGE_SHA_NOT_UNIQUE:0"):
            _reports_exit_code([], "merge_sha")
        with self.assertRaisesRegex(ReceiptError, "TRAIN_RECEIPT_MERGE_SHA_NOT_UNIQUE:2"):
            _reports_exit_code(
                [{"result": "PASS"}, {"result": "PASS"}],
                "merge_sha",
            )

    def test_merge_sha_requires_pass_not_blocked(self):
        self.assertEqual(_reports_exit_code([{"result": "PASS"}], "merge_sha"), 0)
        self.assertEqual(_reports_exit_code([{"result": "BLOCKED"}], "merge_sha"), 1)
        self.assertEqual(_reports_exit_code([{"result": "FAIL"}], "merge_sha"), 1)

if __name__ == "__main__":
    unittest.main(verbosity=2)
