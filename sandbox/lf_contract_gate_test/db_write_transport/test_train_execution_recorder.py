from __future__ import annotations

import pathlib
import subprocess
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
WORKFLOW = ROOT / ".github/workflows/lf-migration-merge-train.yml"
RECORDER = HERE / "lf_train_execution_recorder.py"


class TrainExecutionRecorderTest(unittest.TestCase):
    def test_self_test(self) -> None:
        out = subprocess.run([sys.executable, str(RECORDER), "self-test"], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("PASS_TRAIN_EXECUTION_RECORDER_SELFTEST", out.stdout)

    def test_owner_backfill_system_proposer_manifest_is_scoped(self) -> None:
        import lf_train_execution_recorder as recorder
        ctx = {"pr": "3806", "version": "20261113235900",
               "name": "lf_asset_owner_one_name_backfill_v1",
               "path": "supabase/migrations/20261113235900_lf_asset_owner_one_name_backfill_v1.sql",
               "repo": "cristhianlujan/claude-persona-lf-patch",
               "head_sha": "a"*40, "run_id": "43380001234"}
        manifest = recorder.train_execution_manifest(ctx)
        self.assertEqual(manifest["proposer_actor"], "LF_GOVERNANCE")
        self.assertNotEqual(manifest["proposer_actor"], "Cristhian Luján")
        self.assertEqual(manifest["producer"], "lf-migration-merge-train")
        self.assertEqual(manifest["pr"], 3806)
        self.assertEqual(manifest["head_sha"], "a"*40)
        for key in ("proposer_actor", "decisor", "human_signature"):
            if key != "proposer_actor":
                self.assertNotIn(key, manifest)
        unrelated = dict(ctx, name="lf_other_v1",
                         path="supabase/migrations/20261113235900_lf_other_v1.sql")
        self.assertNotIn("proposer_actor", recorder.train_execution_manifest(unrelated))
        mismatched = [
            dict(ctx, repo="different/repo"),
            dict(ctx, path="supabase/migrations/20261113235900_lf_other_v1.sql"),
            dict(ctx, version="20261114000000")
        ]
        for bad in mismatched:
            with self.subTest(bad=bad), self.assertRaisesRegex(
                    ValueError, "TRAIN_OWNER_BACKFILL_PROPOSER_TARGET_MISMATCH"):
                recorder.train_execution_manifest(bad)

    def test_begin_reserves_existing_train_run_with_documentary_system_proposer(self) -> None:
        import json
        import lf_train_execution_recorder as recorder
        from unittest.mock import patch
        ctx = {"pr":"3806","version":"20261113235900",
               "name":"lf_asset_owner_one_name_backfill_v1",
               "path":"supabase/migrations/20261113235900_lf_asset_owner_one_name_backfill_v1.sql",
               "repo":"cristhianlujan/claude-persona-lf-patch",
               "source_blob":"a"*40,"source_sha256":"b"*64,
               "head_sha":"c"*40,"persisted_head_sha":"c"*40,
               "run_id":"43380001234"}
        captured=[]
        def db(sql, **params):
            if "fn_lf_operation_reserve_execution_v1" in sql:
                captured.append(json.loads(params["manifest"]))
                return {"status":"IN_PROGRESS"}
            if "fn_lf_operation_acquire_lease_v1" in sql:
                return {"result":"LEASE_ACQUIRED","lease_fence":1}
            if "v_lf_capability_entry_guard_v1" in sql:
                return {"entry_guard_state":"GUARDED"}
            if "fn_lf_operation_reserve_effect_v1" in sql:
                return {"dispatch_permitted":True}
            raise AssertionError("UNEXPECTED_TRAIN_DB_CALL:"+sql[:180])
        with patch.object(recorder,"capture_provenance",
                          return_value={"label":"ready-to-merge","diff_class":recorder.DIFF_NO_CHANGE}), \
             patch.object(recorder,"call",side_effect=db), \
             patch.object(recorder,"record_step",return_value=None):
            result=recorder.begin(ctx)
        self.assertEqual(result["result"],"TRAIN_EXECUTION_READY_TO_APPLY")
        self.assertEqual(len(captured),1)
        self.assertEqual(captured[0]["proposer_actor"],"LF_GOVERNANCE")
        self.assertNotIn("decisor",captured[0])

    def test_reservation_idempotency_is_version_scoped(self) -> None:
        source = RECORDER.read_text()
        self.assertIn('idem=f"train:{ctx[\'version\']}:{ctx[\'source_blob\']}"', source)
        self.assertNotIn('idem=f"gitblob:{ctx[\'source_blob\']}"', source)
        self.assertIn("fn_lf_operation_reserve_execution_v1", source)

    def test_workflow_order(self) -> None:
        wf = WORKFLOW.read_text()
        begin = wf.index("Router execution begin or resume (Train-managed, pre-apply)")
        apply = wf.index("- name: Apply exact version and ledger readback")
        commit = wf.index("Router execution patch step (Train-managed, post-apply)")
        parity = wf.index("- name: Run changeset-scoped parity")
        merge = wf.index("- name: Merge exact head only")
        close = wf.index("Router execution verify and close (Train-managed, post-merge)")
        self.assertLess(begin, apply)
        self.assertLess(apply, commit)
        self.assertLess(commit, parity)
        self.assertLess(merge, close)

    def test_abort_only_runs_after_begin_when_apply_did_not_succeed(self) -> None:
        wf = WORKFLOW.read_text()
        block = wf[wf.index("- name: Abort Train execution after pre-apply failure"):]
        block = block[:block.index("- name: Run changeset-scoped parity")]
        self.assertIn("if: failure() && steps.train_exec.outcome == 'success' && steps.real_apply.outputs.applied != 'true'", block)
        self.assertIn('trusted="$RUNNER_TEMP/lf-train-trusted"', block)
        self.assertIn('"$trusted/lf_train_execution_recorder.py" abort', block)
        self.assertIn('--run-id "$GITHUB_RUN_ID"', block)
        self.assertIn('--failed-step "$FAILED_STEP_NAME"', block)
        self.assertIn('--error-summary "$ERROR_SUMMARY"', block)
        self.assertIn("Outputs and credentials are excluded", block)

    def test_resume_applied_exact_does_not_repeat_succeeded_effect_or_clean_patch(self) -> None:
        from unittest.mock import patch
        import lf_train_execution_recorder as recorder

        ctx = {"pr": "2368", "version": "20261013030000", "name": "lf_example_v1",
               "path": "supabase/migrations/20261013030000_lf_example_v1.sql",
               "source_blob": "a" * 40, "source_sha256": "b" * 64, "repo": "o/r",
               "head_sha": "c" * 40, "persisted_head_sha": "d" * 40, "run_id": "987654"}
        candidate = {"execution_id": "EXEC-DB-TRAIN-PR2368-20261013030000-R123",
                     "target_path": ctx["path"], "target_repo": "o/r",
                     "effect_scope": "MIGRATION:20261013030000", "effect_request_sha256": "b" * 64,
                     "dispatch_key": "old-dispatch", "effect_state": "SUCCEEDED",
                     "effect_receipt": {"apply_receipt": {"ok": True}}}
        calls = []
        def fake_call(sql, **params):
            calls.append(sql)
            if "supabase_migrations.schema_migrations" in sql:
                return {"version": ctx["version"], "name": ctx["name"]}
            if "'matches'" in sql:
                return {"matches": [candidate]}
            if "fn_lf_operation_acquire_lease_v1" in sql:
                return {"result": "LEASE_ACQUIRED", "lease_fence": 8}
            if "lf_operation_execution_steps" in sql:
                return {"status": "PASS_CLEAN"}
            raise AssertionError(f"unexpected database call: {sql}")
        with patch.object(recorder, "call", side_effect=fake_call):
            state = recorder.resume(ctx)
            self.assertEqual(state["result"], "TRAIN_EXECUTION_RESUMED")
            self.assertEqual(state["effect_state"], "SUCCEEDED")
            self.assertEqual(state["ids"]["lease_fence"], "8")
            from dataclasses import asdict
            import lf_db_write_transport as transport
            decision = asdict(transport.select_transport("MIGRATION", ctx["path"]))
            recorder.commit(state, decision, state["ledger_receipt"])
        self.assertFalse(any("fn_lf_operation_mark_effect_succeeded_v1" in sql for sql in calls))
        self.assertFalse(any("lf_record_db_operation_step_v1" in sql for sql in calls))
        self.assertTrue(any("lf_operation_execution_steps" in sql for sql in calls))

    def test_failure_receipt_summary_contains_sqlstate_and_sanitized_message(self) -> None:
        import lf_train_execution_recorder as recorder
        summary = recorder.failure_receipt_summary(
            {"sqlstate": "42501", "message": "permission denied for table secret"},
            "See the logs",
        )
        self.assertEqual(summary, "SQLSTATE=42501; message=permission denied for table secret")
        self.assertNotIn("See the logs", summary)
        self.assertEqual(
            recorder.failure_receipt_summary({"sqlstate": "pipel", "message": "pipeline blocked"}, "See logs"),
            "SQLSTATE=NOT_OBSERVED; message=pipeline blocked",
        )

    def test_execution_bookkeeping_verdict_fails_if_close_fails(self) -> None:
        wf = WORKFLOW.read_text()
        block = wf[wf.index("- name: execution bookkeeping verdict"):]
        self.assertIn("if: always()", block)
        self.assertIn('if [ "$COMMIT_OUTCOME" != "success" ] || [ "$CLOSE_OUTCOME" != "success" ]; then', block)
        self.assertIn('body="EXECUTION_BOOKKEEPING_INCOMPLETE $execution_id run $GITHUB_RUN_ID"', block)
        self.assertIn("exit 1", block)

    def test_order_begin_apply_commit_parity_and_merge_close_verdict(self) -> None:
        wf = WORKFLOW.read_text()
        begin = wf.index("Router execution begin or resume (Train-managed, pre-apply)")
        apply = wf.index("- name: Apply exact version and ledger readback")
        commit = wf.index("Router execution patch step (Train-managed, post-apply)")
        parity = wf.index("- name: Run changeset-scoped parity")
        merge = wf.index("- name: Merge exact head only")
        close = wf.index("Router execution verify and close (Train-managed, post-merge)")
        verdict = wf.index("- name: execution bookkeeping verdict")
        self.assertLess(begin, apply)
        self.assertLess(apply, commit)
        self.assertLess(commit, parity)
        self.assertLess(merge, close)
        self.assertLess(close, verdict)

    def test_post_apply_steps_never_block(self) -> None:
        wf = WORKFLOW.read_text()
        for name in ("Router execution patch step (Train-managed, post-apply)",
                     "Router execution verify and close (Train-managed, post-merge)"):
            block = wf[wf.index(name):wf.index(name) + 400]
            self.assertIn("continue-on-error: true", block, name)
        begin = wf[wf.index("Router execution begin or resume (Train-managed, pre-apply)"):]
        begin = begin[:begin.index("- name: Apply exact version")]
        self.assertNotIn("continue-on-error", begin)
        self.assertIn("lf-train-trusted", begin)


if __name__ == "__main__":
    unittest.main()
