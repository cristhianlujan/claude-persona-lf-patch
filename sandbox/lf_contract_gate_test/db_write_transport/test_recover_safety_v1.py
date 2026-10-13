from __future__ import annotations
import os, pathlib, tempfile, unittest
from unittest.mock import patch
import lf_migration_exact_apply as a
import lf_migration_recover_preflight as p

class RecoverSafetyTest(unittest.TestCase):
    def source(self, root):
        version="20261012010000";name="lf_candidate_v1"
        path=pathlib.Path(root)/(version+"_"+name+".sql")
        path.write_text("-- example\nBEGIN;\nselect 1;\nCOMMIT;\n")
        return version,name,path

    def test_router_precedes_rollback_preflight_and_apply(self):
        wf=(pathlib.Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertLess(wf.index("Router execution begin (Train-managed, pre-apply)"),
                        wf.index("- name: RECOVER compatibility preflight with rollback"))
        self.assertLess(wf.index("- name: RECOVER compatibility preflight with rollback"),
                        wf.index("- name: Apply exact version and ledger readback"))
        self.assertIn("LF_RECOVER_AUTHORIZED",wf)
        self.assertIn("steps.recover_preflight.outcome == 'success'",wf)
        self.assertIn("--recover-existing-main",wf)

    def test_missing_train_execution_cannot_enter_recover(self):
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            with self.assertRaisesRegex(RuntimeError,"RECOVER_TRAIN_STATE_FILE_REQUIRED"):
                a._verify_recover_router(db_url="unused",project_root=pathlib.Path(tmp),
                    migration_path=path,source_blob="a"*40,train_state_path=None)

    def test_router_identity_or_authority_cannot_be_spoofed(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            state=pathlib.Path(tmp)/"state.json"
            state.write_text(json.dumps({
                "result":"TRAIN_EXECUTION_READY_TO_APPLY",
                "ids":{"execution_id":"EXEC-EXAMPLE-1"},
                "context":{"path":"supabase/migrations/"+path.name,
                           "source_blob":"a"*40,
                           "source_sha256":"invalid"}
            }))
            with self.assertRaisesRegex(RuntimeError,"RECOVER_TRAIN_EXACT_IDENTITY_UNVERIFIED"):
                a._verify_recover_router(db_url="unused",project_root=pathlib.Path(tmp),
                    migration_path=path,source_blob="a"*40,train_state_path=state)

    def test_historical_version_must_not_use_bulk_push(self):
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            with patch.object(a,"_verify_recover_router"),patch.object(a,"read_ledger",side_effect=[(None,None,None),(version,name,"SOURCE_FIRST")]),patch.object(a,"read_ledger_max",return_value="20261013020000"),patch.object(a,"_fallback_apply") as fallback,patch.object(a,"_primary_cli") as primary,patch.dict(os.environ,{"LF_RECOVER_AUTHORIZED":"TRAIN_PREFLIGHT_PASSED"}):
                result=a.apply_exact(project_root=pathlib.Path(tmp),migration_path=path,
                    db_url="test",source_blob="a"*40,allow_fallback=True,recover_existing_main=True)
                self.assertEqual(result.code,"RECOVER_EXACT_ORIGINAL_APPLIED")
                fallback.assert_called_once();primary.assert_not_called()

    def test_no_train_authority_cannot_apply(self):
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            with patch.object(a,"_verify_recover_router"),patch.object(a,"read_ledger",return_value=(None,None,None)),patch.object(a,"read_ledger_max",return_value="20261013020000"),patch.object(a,"_fallback_apply") as fallback,patch.dict(os.environ,{"LF_RECOVER_AUTHORIZED":"DENY"}):
                with self.assertRaisesRegex(RuntimeError,"RECOVER_TRAIN_PREFLIGHT_AUTHORITY_REQUIRED"):
                    a.apply_exact(project_root=pathlib.Path(tmp),migration_path=path,
                      db_url="test",source_blob="a"*40,allow_fallback=True,recover_existing_main=True)
                fallback.assert_not_called()

    def test_applied_original_must_not_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            with patch.object(a,"_verify_recover_router"),patch.object(a,"read_ledger",return_value=(version,name,"EXISTING")),patch.object(a,"_fallback_apply") as fallback:
                with self.assertRaisesRegex(RuntimeError,"RECOVER_ALREADY_APPLIED"):
                    a.apply_exact(project_root=pathlib.Path(tmp),migration_path=path,
                      db_url="test",source_blob="a"*40,allow_fallback=True,recover_existing_main=True)
                fallback.assert_not_called()

    def test_reject_escaped_transaction_or_psql_command(self):
        dangerous=[
            "BEGIN;\nselect 1;\nCOMMIT;\nCOMMIT;\n",
            "BEGIN;\n\\\\! echo no\nselect 1;\nCOMMIT;\n",
            "BEGIN;\nselect 1;\nROLLBACK;\nCOMMIT;\n"
        ]
        for sql in dangerous:
            with self.subTest(sql=sql):
                for fn in (p.strip_outer_transaction,a._strip_outer_transaction):
                    with self.assertRaises(ValueError):
                        fn(sql)

    def test_transaction_wrapper_is_not_replayed_inside_outer_transaction(self):
        sql="-- source\nBEGIN;\nselect 1;\nCOMMIT;\n"
        out=a.build_fallback_sql(version="20261012010000",name="lf_candidate_v1",
              source_sql=sql,source_blob="a"*40,recover_existing_main=True)
        self.assertIn("if not true and v_max",out)
        self.assertIn("array[$lfmig",out)
        self.assertEqual(p.strip_outer_transaction(sql),a._strip_outer_transaction(sql))

if __name__=="__main__":unittest.main()
