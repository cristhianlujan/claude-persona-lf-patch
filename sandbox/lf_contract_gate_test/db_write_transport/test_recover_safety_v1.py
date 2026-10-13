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

    def _simulate_controlled_rollback(self, *, initial_count=0, final_floor=None, bad_digest=False):
        import json,sys
        from contextlib import redirect_stdout
        from io import StringIO
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            source_sha="f"*64 if bad_digest else __import__("hashlib").sha256(path.read_bytes()).hexdigest()
            state_path=pathlib.Path(tmp)/"train-state.json"
            state_path.write_text(json.dumps({
                "result":"TRAIN_EXECUTION_READY_TO_APPLY",
                "context":{"version":version,"name":name,"path":"supabase/migrations/"+path.name,
                           "source_sha256":source_sha},
                "ids":{"execution_id":"EXEC-TRAIN-TEST-1","effect_scope":"MIGRATION:"+version}
            }))
            queries=[]
            reads=[{"target_count":initial_count,"ledger_max":"20261013020004"},
                   {"target_count":0,"ledger_max":final_floor or "20261013020004"}]
            def fake_psql(url,sql):
                queries.append(sql)
                if "lf_router_downstream_authority_validate_v1" in sql:
                    return json.dumps({"applicable":True,"valid":True,
                        "code":"ROUTER_DOWNSTREAM_AUTHORITY_VALID",
                        "operation_code":"ACTUALIZACION_DB_LF","target_type":"MIGRATION",
                        "target_code":version+"_"+name})
                if sql.startswith("begin;"):
                    if not sql.rstrip().endswith("rollback;"):
                        raise AssertionError("RECOVER_ROLLBACK_NOT_TERMINAL")
                    return "BEGIN\nROLLBACK"
                return json.dumps(reads.pop(0))
            argv=["preflight","--migration-path",str(path),"--train-state",str(state_path),"--db-url","sandbox-simulation"]
            with patch.object(p,"psql",side_effect=fake_psql),patch.object(sys,"argv",argv):
                with redirect_stdout(StringIO()) as capture:
                    if bad_digest:
                        with self.assertRaisesRegex(RuntimeError,"RECOVER_ROUTER_TRAIN_IDENTITY_MISMATCH"):
                            p.main()
                    elif initial_count:
                        with self.assertRaisesRegex(RuntimeError,"RECOVER_TARGET_ALREADY_IN_LEDGER"):
                            p.main()
                    elif final_floor:
                        with self.assertRaisesRegex(RuntimeError,"RECOVER_PREFLIGHT_LEFT_LEDGER_RESIDUE"):
                            p.main()
                    else:
                        self.assertEqual(p.main(),0)
                        self.assertEqual(json.loads(capture.getvalue())["code"],"RECOVER_COMPATIBILITY_ROLLBACK_PASS")
            rollback_calls=[q for q in queries if q.startswith("begin;")]
            self.assertEqual(len(rollback_calls),0 if (bad_digest or initial_count) else 1)
            self.assertTrue(all("rollback;" in q for q in rollback_calls))
            return queries

    def test_controlled_rollback_success_without_database(self):
        calls=self._simulate_controlled_rollback()
        self.assertEqual(len(calls),4)

    def test_controlled_rollback_rejects_wrong_source_before_db(self):
        calls=self._simulate_controlled_rollback(bad_digest=True)
        self.assertEqual(calls,[])

    def test_controlled_rollback_blocks_applied_original(self):
        calls=self._simulate_controlled_rollback(initial_count=1)
        self.assertFalse(any(q.startswith("begin;") for q in calls))

    def test_controlled_rollback_detects_ledger_residue(self):
        calls=self._simulate_controlled_rollback(final_floor="20261014000000")
        self.assertEqual(len([q for q in calls if q.startswith("begin;")]),1)
    def test_router_precedes_rollback_preflight_and_apply(self):
        wf=(pathlib.Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertLess(wf.index("Router execution begin (Train-managed, pre-apply)"),
                        wf.index("- name: RECOVER compatibility preflight with rollback"))
        self.assertLess(wf.index("- name: RECOVER compatibility preflight with rollback"),
                        wf.index("- name: Apply exact version and ledger readback"))
        self.assertLess(wf.index("- name: Router execution begin (Train-managed, pre-apply)"),
                        wf.index("- name: RECOVER verify Saga with Router execution identity"))
        self.assertLess(wf.index("- name: RECOVER verify Saga with Router execution identity"),
                        wf.index("- name: RECOVER compatibility preflight with rollback"))
        self.assertIn('"execution_id":ids["execution_id"]',wf)
        self.assertNotIn('"execution_id":"EXEC-TRAIN-RECOVER-',wf)
        self.assertIn("LF_RECOVER_AUTHORIZED",wf)
        self.assertIn("steps.recover_preflight.outcome == 'success'",wf)
        self.assertIn("--recover-existing-main",wf)

    def test_canonical_parity_exact_and_negative_readback(self):
        import json,sys
        from contextlib import redirect_stdout
        from io import StringIO
        with tempfile.TemporaryDirectory() as tmp:
            version,name,path=self.source(tmp)
            ledger={"version":version,"name":name,"statement_count":1,
                    "statement_hex":path.read_bytes().hex()}
            argv=["recover","--migration-path",str(path),"--db-url","test","--readback"]
            with patch.object(p,"psql",return_value=json.dumps(ledger)),patch.object(sys,"argv",argv):
                with redirect_stdout(StringIO()) as out:
                    self.assertEqual(p.main(),0)
                data=json.loads(out.getvalue())
                self.assertEqual(data["parity_code"],"PASS_LF_MIGRATION_SOURCE_PARITY")
                self.assertEqual(data["parity_version_count"],1)
            ledger["statement_hex"]=b"select 999;".hex()
            with patch.object(p,"psql",return_value=json.dumps(ledger)),patch.object(sys,"argv",argv):
                with self.assertRaisesRegex(RuntimeError,"RECOVER_EXACT_LEDGER_CONTENT_MISMATCH"):
                    p.main()

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
