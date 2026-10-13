from __future__ import annotations
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import json, subprocess, sys, tempfile, unittest
from unittest.mock import patch
import lf_migration_reconcile_git as m

OLD="supabase/migrations/20261012040000_ig_example_v1.sql"
NEW="supabase/migrations/20261012012743_ig_example_v1.sql"

def git(root,*args):
    p=subprocess.run(["git",*args],cwd=root,capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()

class ReconcileGitOnlyTest(unittest.TestCase):
    def prepare(self, status="renamed", mutate=False, extra=False, source_sql="select 1;\n"):
        tmp=tempfile.TemporaryDirectory()
        root=Path(tmp.name)
        git(root,"init","-q");git(root,"config","user.email","tests@example.test");git(root,"config","user.name","Tests")
        p=root/OLD;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(source_sql)
        git(root,"add",".");git(root,"commit","-qm","original")
        base=git(root,"rev-parse","HEAD")
        p.rename(root/NEW)
        if mutate:(root/NEW).write_text("select 2;\n")
        git(root,"add","-A");git(root,"commit","-qm","rename")
        head=git(root,"rev-parse","HEAD")
        rows=[{"status":status,"filename":NEW,"previous_filename":OLD}]
        if extra:rows.append({"status":"modified","filename":"README.md"})
        file=root/"changed.json";file.write_text(json.dumps([rows]))
        return tmp,root,file,base,head

    def run_case(self,*,status="renamed",mutate=False,extra=False,source_sql="select 1;\n",ledger=None):
        tmp,root,changes,base,head=self.prepare(status=status,mutate=mutate,extra=extra,source_sql=source_sql)
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),"--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","test-db"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router") as auth,patch.object(m,"ledger_row",return_value=ledger or ("ig_example_v1","select 1;\n",1)):
                with redirect_stdout(StringIO()) as out:
                    m.main()
                return json.loads(out.getvalue()),auth.call_count
        finally:
            tmp.cleanup()

    def test_mode_contract_extends_existing_judge_without_promoting(self):
        root=Path(__file__).resolve().parents[3]
        path=root/"docs/migrations/LF_TRAIN_RECONCILE_JUDGE_EXTENSION_CANDIDATE_V1.json"
        candidate=json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(candidate["status"],"CANDIDATE_NOT_REGISTERED_NOT_ACTIVE")
        self.assertEqual(candidate["operation_code"],"ACTUALIZACION_DB_LF")
        self.assertEqual(candidate["mode"],"RECONCILE_GIT_ONLY")
        self.assertEqual(candidate["authority_boundary"]["entry"],"ACT-0001")
        self.assertFalse(candidate["authority_boundary"]["db_writes_allowed"])
        self.assertFalse(candidate["authority_boundary"]["ledger_dml_allowed"])
        self.assertEqual(candidate["existing_bindings_not_to_override"]["judge_code"],"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1")
        self.assertEqual(sorted(candidate["proposed_mode_judge"]),["patch","preflight","verify"])
        self.assertEqual(candidate["implementation_state"]["git_only_closeout"],"NOT_IMPLEMENTED")
    def test_train_routes_reconcile_without_db_apply(self):
        wf=(Path(__file__).resolve().parents[3]/".github/workflows/lf-migration-merge-train.yml").read_text()
        self.assertLess(wf.index("- name: Resolve RECONCILE governed mode"),
                        wf.index("- name: Sync PR branch with current main in REAL mode"))
        self.assertIn("RECONCILE_GIT_ONLY_PASS",wf)
        gate = wf.index("- name: Block RECONCILE promotion until governed Git-only closeout exists")
        publish = wf.index("- name: Publish lf-merge-train/verified before REAL merge")
        merge = wf.index("- name: Merge exact head only")
        self.assertLess(gate,publish)
        self.assertLess(publish,merge)
        self.assertIn("BLOCK_RECONCILE_GIT_ONLY_CLOSURE_JUDGE_NOT_ADMITTED",wf[gate:publish])
        self.assertIn("exit 2",wf[gate:publish])
        self.assertIn("migration_count=0",wf)
        self.assertIn("--router-execution-id",wf)
        self.assertIn("steps.reconcile_mode.outputs.mode != 'RECONCILE'",wf)
        self.assertIn("RECONCILE_MIXED_SCOPE_FORBIDDEN",(Path(__file__).resolve().parent/"lf_migration_reconcile_git.py").read_text())

    def test_multi_statement_ledger_blocks_without_any_write(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),
                  "--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 1;\n",2)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_CANONICAL_PARITY_FAILED"):
                    m.main()
        finally:
            tmp.cleanup()

    def test_ledger_sql_mismatch_is_rejected_by_canonical_core(self):
        tmp,root,changes,base,head=self.prepare()
        try:
            args=["test","--repo-root",str(root),"--pr-files",str(changes),
                  "--base-sha",base,"--head-sha",head,
                  "--router-execution-id","EXEC-RECONCILE-1","--repository","o/r","--db-url","read-only"]
            with patch.object(sys,"argv",args),patch.object(m,"validate_router"),\
                 patch.object(m,"ledger_row",return_value=("ig_example_v1","select 99;\n",1)):
                with self.assertRaisesRegex(RuntimeError,"RECONCILE_CANONICAL_PARITY_FAILED"):
                    m.main()
        finally:
            tmp.cleanup()
    def test_cli_multi_statement_ledger_representation_passes(self):
        sql="select 1;\nselect 2;\n"
        got,auth=self.run_case(source_sql=sql,ledger=("ig_example_v1","select 1\nselect 2",2))
        self.assertEqual(got["code"],"RECONCILE_GIT_ONLY_PASS")
        self.assertEqual(auth,1)

    def test_inconsistent_ledger_statement_payload_is_rejected(self):
        record={"name":"ig_example_v1","statement_count":2,"statements":["select 1;"]}
        with patch.object(m,"read_only_query",return_value=[json.dumps(record)]):
            with self.assertRaisesRegex(RuntimeError,"RECONCILE_LEDGER_STATEMENT_PAYLOAD_INVALID"):
                m.ledger_row("fake-read-only","20261012012743")
    def test_git_only_exact_content_passes(self):
        got,auth=self.run_case()
        self.assertEqual(got["code"],"RECONCILE_GIT_ONLY_PASS")
        self.assertEqual(got["count"],1)
        self.assertEqual(auth,1)

    def test_sql_changed_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_CONTENT_CHANGED"):
            self.run_case(mutate=True)

    def test_nonrename_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_NOT_RENAME_ONLY"):
            self.run_case(status="modified")

    def test_mixed_scope_blocks(self):
        with self.assertRaisesRegex(RuntimeError,"RECONCILE_MIXED_SCOPE_FORBIDDEN"):
            self.run_case(extra=True)

    def test_invalid_router_receipt_blocks(self):
        receipt={"status":"IN_PROGRESS","operation_code":"ACTUALIZACION_DB_LF","target_type":"MIGRATION",
                 "target_code":"RECONCILE_GIT_ONLY","target_repo":"o/r","target_path":"supabase/migrations",
                 "source_base":"a"*40,"source_head":"b"*40,
                 "authority":{"applicable":True,"valid":False,"code":"ROUTER_DOWNSTREAM_AUTHORITY_NOT_BOUND"}}
        with patch.object(m,"read_only_query",return_value=[json.dumps(receipt)]):
            with self.assertRaisesRegex(RuntimeError,"ROUTER_AUTHORITY_NOT_VALID"):
                m.validate_router("test","EXEC-RECONCILE-1","o/r","a"*40,"b"*40)

if __name__=="__main__":unittest.main()
