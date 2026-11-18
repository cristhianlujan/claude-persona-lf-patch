#!/usr/bin/env python3
"""IG4064 exact-head advisory dispatch: static positive/negative tests only.

The trusted live PG BEGIN/ROLLBACK integration is separately gated on main.
These tests never connect to Supabase, publish statuses or create receipts.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/s28_ci_lane_router"))
import lf_pase_merge_route_v1 as route
import lf_repository_path_admission as admission
import ig4064_rollback_runner_v1 as runner

WF=".github/workflows/lf-router-level2-advisory-tests.yml"
WORKFLOW=ROOT/WF
SCRIPT=HERE/"ig4064_rollback_runner_v1.py"
TEMPLATE=HERE/"ig4064_rollback_template_v1.sql"
TEST=HERE/"test_ig4064_advisory_dispatch_v1.py"

def blob(s: str) -> str:
    raw=s.encode()
    return hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\x00"+raw).hexdigest()

class IG4064AdvisoryPathTests(unittest.TestCase):
    def test_01_existing_workflow_path_positive(self):
        self.assertEqual(admission.load_repository_path_admission().evaluate(WF),{
            "verdict":"ADMIT","code":"PASS_GITHUB_EXACT_PATH_ADMISSION"})
        self.assertEqual(json.loads((ROOT/"sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json").read_text())["path_admission"]["default_github"],"DENY")

    def test_02_new_workflow_path_negative(self):
        self.assertEqual(admission.load_repository_path_admission().evaluate(".github/workflows/lf-ig-4064-live-rollback.yml"),{
            "verdict":"BLOCK","code":"FAIL_UNAUTHORIZED_GITHUB_PATH"})
        self.assertEqual(admission.load_repository_path_admission().evaluate(".github/workflows/lf-router-level2-advisory-tests-copy.yml"),{
            "verdict":"BLOCK","code":"FAIL_UNAUTHORIZED_GITHUB_PATH"})

    def test_03_existing_path_routes_execution_plan(self):
        paths=[WF,*[str(p.relative_to(ROOT)).replace(os.sep,"/") for p in (SCRIPT,TEMPLATE,TEST)]]
        self.assertEqual(route.classify_route(paths,route.load_registry()),("EXECUTION_PLAN",None))

    def test_04_control_system_registry_still_needs_qualification(self):
        path="sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"
        self.assertEqual(route.classify_route([path],route.load_registry()),
                         ("CONTROL_SYSTEM_QUALIFICATION","CHANGESET_GOVERNANCE_LF_V1"))

    def test_05_sql_has_one_begin_one_rollback_no_commit(self):
        s=TEMPLATE.read_text()
        self.assertEqual(s.splitlines().count("BEGIN;"),1)
        self.assertEqual(s.splitlines().count("ROLLBACK;"),1)
        self.assertNotIn("\nCOMMIT;",s)
        for term in ("IG4064_RECALL_PASS","IG4064_NA_REFS_PASS",
                     "IG4064_OTHER_39_REGRESSION_PASS","IG4064_POST_ROLLBACK_PASS"):
            self.assertIn(term,s)

    def test_06_manual_dispatch_and_protected_job(self):
        s=WORKFLOW.read_text()
        self.assertIn("ig4064_rollback_only:",s)
        self.assertIn("github.ref == 'refs/heads/main'",s)
        self.assertIn("environment: lf-merge-train",s)
        self.assertIn("PGPASSWORD:",s)
        self.assertIn("github.event_name == 'workflow_dispatch'",s)
        self.assertIn("actions/upload-artifact@v4",s)
        self.assertIn("IG4064_ADVISORY_STATIC_NEGATIVE_POSITIVE_PASS",s)

    def test_07_exact_candidate_hash_pin(self):
        self.assertEqual(runner.HEAD,"ade493bbd425a337dc81d175410eff2abea956f0")
        self.assertEqual(runner.BLOBS[runner.MIGRATION],"370bfb1682bac0ca8e30f9cef179f7939d5a659f")
        self.assertEqual(runner.BLOBS[runner.HARNESS],"3df03ef574f2cd6e653ab7c38194c8bc04f6851d")
        self.assertEqual(runner.TEMPLATE,TEMPLATE.relative_to(ROOT))
        self.assertIn("COMMIT_FORBIDDEN",SCRIPT.read_text())

    def test_08_reject_commit_and_unpinned_sql(self):
        m="DO $ig$\nBEGIN\nRAISE NOTICE 'ok';\nEND;\n$ig$;\n"
        h=("\\set ON_ERROR_STOP on\nBEGIN;\n\\ir ../../supabase/migrations/20261117073400_lf_ig_recovery_family_positive_na_v1.sql\n"
           "DO $test$\nBEGIN\nRAISE NOTICE 'ok';\nEND;\n$test$;\nROLLBACK;\n")
        cwd=Path.cwd()
        with tempfile.TemporaryDirectory(prefix="ig4064-safety-") as tmp:
            root=Path(tmp)/"candidate-readonly"
            for fn,txt in ((runner.MIGRATION,m),(runner.HARNESS,h)):
                p=root/fn;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(txt)
            fake_hash={runner.MIGRATION:blob(m),runner.HARNESS:blob(h)}
            try:
                os.chdir(tmp)
                with mock.patch.object(runner,"BLOBS",fake_hash),mock.patch.object(
                        runner.subprocess,"check_output",return_value=runner.HEAD+"\n"):
                    self.assertEqual(runner.exact_sql()[0],m.strip())
                    p=root/runner.MIGRATION
                    p.write_text(m.replace("RAISE NOTICE 'ok';","COMMIT;"))
                    with self.assertRaisesRegex(RuntimeError,"PINNED_BLOB_DRIFT"):
                        runner.exact_sql()
                    p.write_text(m.replace("RAISE NOTICE 'ok';","COMMIT;"))
                    new={**fake_hash,runner.MIGRATION:blob(p.read_text())}
                    with mock.patch.object(runner,"BLOBS",new):
                        with self.assertRaisesRegex(RuntimeError,"TRANSACTION_CONTROL_FORBIDDEN"):
                            runner.exact_sql()
            finally:os.chdir(cwd)

    def test_09_real_assembled_sql_accepts_temp_table_commit_clauses(self):
        # The checkout at candidate-readonly is the exact immutable #4064 HEAD.
        # No SQL is executed against PostgreSQL in this test.
        sql, digests = runner.assembled_sql()
        self.assertEqual(digests[runner.MIGRATION],
                         "8677dce173327175341b50075d9d1eddd3452d50541ba252f359a4ef0d2e279c")
        self.assertEqual(digests[runner.HARNESS],
                         "4e13b49f2cf5d91a41e5aa0b972b0d72023052f72f17b23a799d849895ec49a9")
        self.assertIn("ON COMMIT DROP", sql)
        self.assertIn("DO $ig$", sql)
        self.assertIn("DO $test$", sql)
        self.assertIn("IG4064_TX_ROLLBACK_DONE", sql)
        statements = runner.top_level_sql_statements(sql)
        self.assertEqual(sum(head[0] == "BEGIN" for head in statements), 1)
        self.assertEqual(sum(head[0] == "ROLLBACK" for head in statements), 1)
        self.assertTrue(any(head[:2] == ("CREATE", "TEMP") and
                            "COMMIT" in head for head in statements))
        print("PASS_IG4064_REAL_ASSEMBLED_SQL_GUARD "
              f"head={runner.HEAD} statements={len(statements)} "
              f"sql_sha256={runner.sha256(sql.encode())} "
              f"migration_sha256={digests[runner.MIGRATION]} "
              f"harness_sha256={digests[runner.HARNESS]}")

    def test_10_real_assembled_sql_rejects_commit_commands(self):
        sql, _ = runner.assembled_sql()
        injection_marker = r"\echo IG4064_TX_ROLLBACK_START"
        self.assertEqual(sql.count(injection_marker), 1)
        # Inject genuine top-level SQL into the complete real #4064 script.
        dangerous = (
            "COMMIT;",
            "COMMIT AND CHAIN;",
            "END;",
            "END WORK;",
            "COMMIT PREPARED 'ig-test-gid';",
            "PREPARE TRANSACTION 'ig-test-gid';",
            "ROLLBACK PREPARED 'ig-test-gid';",
        )
        for command in dangerous:
            injected = sql.replace(injection_marker, command + "\n" +
                                   injection_marker, 1)
            with self.assertRaisesRegex(RuntimeError, "^COMMIT_FORBIDDEN$",
                                        msg=command):
                runner.assert_safe_transaction_control(injected)
        # These are SQL data/syntax, not transaction-ending commands.
        benign = (
            "CREATE TEMP TABLE ig4064_test_delete(x text) ON COMMIT DELETE ROWS;",
            "CREATE TEMP TABLE ig4064_test_drop(x text) ON COMMIT DROP;",
            "SELECT 'COMMIT; END; PREPARE TRANSACTION', $q$COMMIT; END;$q$;",
            "/* COMMIT; /* END; */ PREPARE TRANSACTION 'x'; */",
            "-- COMMIT AND CHAIN;\nSELECT 'END;';",
        )
        for statement in benign:
            candidate = sql.replace(injection_marker, statement + "\n" +
                                    injection_marker, 1)
            runner.assert_safe_transaction_control(candidate)
        print("PASS_IG4064_REAL_ASSEMBLED_SQL_NEGATIVE "
              f"blocked={len(dangerous)}/{len(dangerous)} "
              f"benign_accepted={len(benign)}/{len(benign)} "
              f"original_sha256={runner.sha256(sql.encode())}")

    def test_11_independent_readback_exact_comment_boundary(self):
        # Real template has prose on the SAME line as the trusted marker.
        sql=TEMPLATE.read_text()
        block=runner.independent_readback_sql(sql)
        self.assertTrue(block.startswith("DO $post$\n"))
        self.assertTrue(block.rstrip().endswith("$post$;"))
        self.assertNotIn("Fail if definitions or historical rows drifted.",block)
        self.assertEqual(runner.top_level_sql_statements(block),[("DO",)])
        self.assertIn("IG4064_POST_ROLLBACK_PASS",block)

    def test_12_independent_readback_negative_untrusted_sql(self):
        template=TEMPLATE.read_text()
        marker="-- Same psql session, AFTER rollback."
        self.assertEqual(template.count(marker),1)
        bad_cases={
            "missing":template.replace(marker,"-- wrong marker",1),
            "duplicate":template+ "\n" + marker+" another copy\n",
            "unterminated":template.split(marker,1)[0]+marker,
            "prose_as_sql":template.replace(
                marker+" Fail if definitions or historical rows drifted.\n",
                marker+"\nFail if definitions or historical rows drifted.\n",1),
            "extra_sql":template.replace(
                marker+" Fail if definitions or historical rows drifted.\n",
                marker+" note\nSELECT 1;\n",1),
            "no_post_do":template.replace("DO $post$","DO $other$",1),
            "trailing_sql":template+"\nSELECT 1;\n",
        }
        for name,sql in bad_cases.items():
            with self.subTest(case=name):
                with self.assertRaisesRegex(RuntimeError, "INDEPENDENT_READBACK_"):
                    runner.independent_readback_sql(sql)

    def test_13_trusted_source_pins_exact_not_dynamic(self):
        self.assertEqual(runner.PR,4064)
        self.assertEqual(runner.HEAD,"ade493bbd425a337dc81d175410eff2abea956f0")
        self.assertEqual(runner.BLOBS,{
            runner.MIGRATION:"370bfb1682bac0ca8e30f9cef179f7939d5a659f",
            runner.HARNESS:"3df03ef574f2cd6e653ab7c38194c8bc04f6851d",
        })
        self.assertIn("PR4064_LIVE_HEAD_DRIFT",SCRIPT.read_text())
        self.assertIn("PINNED_BLOB_DRIFT:",SCRIPT.read_text())


if __name__=="__main__":
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(IG4064AdvisoryPathTests)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():print("IG4064_ADVISORY_STATIC_NEGATIVE_POSITIVE_PASS 13/13")
    raise SystemExit(0 if result.wasSuccessful() else 1)
